# AR Capture System — Full Developer Guide

> **Purpose:** This document explains every part of the AR Capture feature in the Midwife app — how the screens work, how the machine learning pipeline runs, how Firebase stores the results, and how all the pieces connect together.

---

## Table of Contents

1. [What Is AR Capture?](#1-what-is-ar-capture)
2. [High-Level Flow Diagram](#2-high-level-flow-diagram)
3. [Project File Structure](#3-project-file-structure)
4. [Data Models — The Building Blocks](#4-data-models--the-building-blocks)
5. [Screen-by-Screen Walkthrough](#5-screen-by-screen-walkthrough)
   - 5.1 [ARCaptureMainScreen — The Orchestrator](#51-arcapturemainscreen--the-orchestrator)
   - 5.2 [LanguageSelectionScreen](#52-languageselectionscreen)
   - 5.3 [ModeSelectionScreen](#53-modeselectionscreen)
   - 5.4 [ChildDetailsScreen](#54-childdetailsscreen)
   - 5.5 [HowToScanScreen](#55-howtoscanscreen)
   - 5.6 [HeadCaptureScreen](#56-headcapturescreen)
   - 5.7 [PostureCaptureScreen](#57-posturecapturescreen)
   - 5.8 [DiagnosisScreen](#58-diagnosisscreen)
   - 5.9 [GeometricToolScreen](#59-geometrictoolscreen)
   - 5.10 [ARReportsListScreen](#510-arreportslistscreen)
6. [Widgets](#6-widgets)
   - 6.1 [CameraView Widget](#61-cameraview-widget)
7. [ML & AI Services](#7-ml--ai-services)
   - 7.1 [MLService — TFLite Inference Engine](#71-mlservice--tflite-inference-engine)
   - 7.2 [CranialAnalysisService — Head Screening](#72-cranialanalysisservice--head-screening)
   - 7.3 [HeadLandmarkerRuntime — MediaPipe Bridge](#73-headlandmarkerruntime--mediapipe-bridge)
   - 7.4 [CranialMetrics — Geometry Math](#74-cranialmetrics--geometry-math)
   - 7.5 [PostureScreeningService — Body Analysis](#75-posturescreeningservice--body-analysis)
   - 7.6 [GeminiCranioService — AI Visual Analysis](#76-geminicranioservice--ai-visual-analysis)
   - 7.7 [ClassifierService — Binary Output](#77-classifierservice--binary-output)
   - 7.8 [ScanReportLogger — Local Logging](#78-scanreportlogger--local-logging)
8. [Firebase Setup & Integration](#8-firebase-setup--integration)
   - 8.1 [Project Configuration](#81-project-configuration)
   - 8.2 [Authentication Flow](#82-authentication-flow)
   - 8.3 [Firestore Data Structure](#83-firestore-data-structure)
   - 8.4 [ChildReportService — Reading & Writing Reports](#84-childreportservice--reading--writing-reports)
   - 8.5 [Firestore Security Rules](#85-firestore-security-rules)
9. [Assets & Dependencies](#9-assets--dependencies)
10. [End-to-End Worked Example](#10-end-to-end-worked-example)
11. [Risk Band Reference](#11-risk-band-reference)
12. [Bilingual Support (EN / සිං)](#12-bilingual-support-en--)
13. [Platform Differences](#13-platform-differences)

---

## 1. What Is AR Capture?

AR Capture is a clinical screening tool built into the Midwife app. A community midwife points the phone camera at an infant and the app:

1. Guides the midwife to capture the correct angle (head-on or full-body).
2. Runs on-device AI models to measure skull shape or body posture.
3. Gives a traffic-light risk result (Green / Amber / Red).
4. Saves the result to Firebase so doctors can review it later.

There are **two screening modes**:

| Mode | What it checks | Medical concern |
|---|---|---|
| **Head Analysis** | Skull shape, cranial symmetry, facial balance | Craniosynostosis / plagiocephaly |
| **Posture Analysis** | Shoulder tilt, hip tilt, trunk and head alignment | Postural asymmetry, scoliosis risk |

All AI inference runs **on the device** (no internet needed for ML). Firebase is only used to save and retrieve completed reports.

---

## 2. High-Level Flow Diagram

```
App Start
    │
    ▼
/ar-capture route
    │
    ▼
ARCaptureMainScreen  ◄─── manages all screen state
    │
    ├─► LanguageSelectionScreen  (EN or Sinhala)
    │        │ onLanguageSelected
    │        ▼
    ├─► ModeSelectionScreen  (Head or Posture)
    │        │ onModeSelected
    │        ▼
    ├─► HeadCaptureScreen ─── OR ─── PostureCaptureScreen
    │        │ Camera → take photo → file path
    │        │ MLService.runInference(path, mode)
    │        │ returns confidence int (0-100)
    │        │ onCapture(confidence)
    │        ▼
    ├─► DiagnosisScreen  (traffic light result)
    │        │
    │        ├─ Normal (0-40%)  → Save & Finish
    │        │       │ ChildReportService.addReport(...)
    │        │       ▼ Firebase Firestore
    │        │
    │        ├─ Inconclusive (40-80%)  → Force Retake
    │        │
    │        └─ Abnormal Head (80-100%) → Retake or Home
    │           Abnormal Posture        → GeometricToolScreen
    │
    └─► ARReportsListScreen  (/child-reports route)
             │ ChildReportService.getReports()
             ▼ Firebase Firestore  (reads saved reports)
```

---

## 3. Project File Structure

```
my_flutter_app/
├── lib/
│   ├── screens/
│   │   └── ar_capture/
│   │       ├── ar_capture_main_screen.dart   ← main controller
│   │       ├── ar_capture_models.dart         ← all data classes & enums
│   │       ├── ar_capture_localization.dart   ← translation strings
│   │       ├── language_selection_screen.dart
│   │       ├── mode_selection_screen.dart
│   │       ├── child_details_screen.dart
│   │       ├── how_to_scan_screen.dart
│   │       ├── head_capture_screen.dart
│   │       ├── posture_capture_screen.dart
│   │       ├── diagnosis_screen.dart
│   │       ├── geometric_tool_screen.dart
│   │       └── ar_reports_list_screen.dart
│   │
│   ├── services/
│   │   ├── ar_capture/
│   │   │   ├── ml_service.dart               ← TFLite model runner
│   │   │   ├── cranial_analysis_service.dart  ← head screening logic
│   │   │   ├── cranial_metrics.dart           ← geometry math
│   │   │   ├── head_landmarker_runtime.dart   ← Android MediaPipe bridge
│   │   │   ├── posture_screening.dart         ← body pose analysis
│   │   │   ├── gemini_cranio_service.dart     ← Gemini AI visual analysis
│   │   │   ├── classifier_service.dart        ← simple binary classifier
│   │   │   └── scan_report_logger.dart        ← local JSON logging
│   │   └── child_report_service.dart          ← Firebase read/write
│   │
│   ├── widgets/
│   │   └── ar_capture/
│   │       └── camera_view.dart              ← camera UI + AR overlays
│   │
│   └── firebase_options.dart                 ← Firebase project config
│
├── assets/
│   └── models/
│       ├── cranial_analysis.tflite   (8.87 MB)
│       ├── posture_analysis.tflite   (12.58 MB)
│       └── face_landmarker.task      (3.76 MB)
│
└── app.env                           ← API keys (GEMINI_API_KEY)
```

---

## 4. Data Models — The Building Blocks

**File:** [ar_capture_models.dart](my_flutter_app/lib/screens/ar_capture/ar_capture_models.dart)

All enums and result classes live here. Understanding these is key to understanding the whole system.

### Enums

```dart
// Which screen is currently showing inside ARCaptureMainScreen
enum ScreenState {
  languageSelection,   // Step 1: pick language
  modeSelection,       // Step 2: pick head or posture
  capture,             // Step 3: camera screen
  diagnosis,           // Step 4: result screen
  geometricTool        // Step 5 (optional): angle measurement tool
}

// Which type of scan is being done
enum AppMode { head, posture, none }

// UI language
enum AppLanguage { en, si }

// The final clinical risk level
enum RiskBand { lowRisk, review, refer, unavailable }
```

### HeadScreeningMetrics

Stores every measurement extracted from a head scan. Created by `CranialAnalysisService`.

```dart
class HeadScreeningMetrics {
  final double cranialIndex;              // head width / head length ratio
  final double cranialVaultAsymmetryIndex; // CVAI - diagonal difference
  final double facialSymmetryOffsetPct;   // how uneven the two halves are
  final double cephalicProportionScore;   // overall head shape score
  final double landmarkQuality;           // how reliable the landmarks were
  final double topDownAngleDelta;         // camera tilt error

  // Optional - only set when AI analysis runs
  final String? aiRiskLevel;     // "low" / "moderate" / "high"
  final int? aiRiskScore;        // 0-100
  final String? headShapeLabel;  // e.g. "plagiocephaly"
  final List<String>? keyFindings;
  final String? recommendation;
  final String? visualObservations;
  ...
}
```

### PostureScreeningMetrics

Stores body pose angles extracted from a posture scan.

```dart
class PostureScreeningMetrics {
  final double shoulderTiltDeg;    // left vs right shoulder height difference
  final double hipTiltDeg;         // left vs right hip height difference
  final double trunkTiltDeg;       // overall body lean
  final double headTiltDeg;        // head tilt relative to body
  final double midlineOffsetRatio; // how far off-center the body is
  final double visibilityQuality;  // 0-100, how well the body was detected
  final double cameraRollDeg;      // how much the camera was rotated
}
```

### ARCaptureResult

The final unified result object — returned by both head and posture analysis, saved to Firebase.

```dart
class ARCaptureResult {
  final bool isValidImage;         // did the image pass all validation checks?
  final bool supportedView;        // was the camera angle acceptable?
  final int qualityScore;          // 0-100: image capture quality
  final int screeningScore;        // 0-100: risk indicator
  final RiskBand riskBand;         // lowRisk / review / refer / unavailable
  final String summary;            // human-readable explanation
  final List<String> warnings;     // list of specific problems found

  final HeadScreeningMetrics? headMetrics;     // set for head mode
  final PostureScreeningMetrics? postureMetrics; // set for posture mode
  ...
}
```

The `invalid()` factory constructor is used when a scan fails completely:

```dart
ARCaptureResult.invalid(
  summary: 'No face detected in image',
  warnings: ['Try better lighting', 'Ensure full face is visible'],
)
// Returns: isValidImage=false, screeningScore=0, riskBand=unavailable
```

---

## 5. Screen-by-Screen Walkthrough

### 5.1 ARCaptureMainScreen — The Orchestrator

**File:** [ar_capture_main_screen.dart](my_flutter_app/lib/screens/ar_capture/ar_capture_main_screen.dart)

This is the single `StatefulWidget` that **owns all the state** for the entire AR capture flow. It never navigates using `Navigator.push` — instead it swaps out child widgets by changing `_currentScreen`.

**State variables:**

```dart
ScreenState _currentScreen = ScreenState.languageSelection; // which screen to show
AppMode _mode = AppMode.none;       // head or posture
AppLanguage _language = AppLanguage.en;  // EN or Sinhala
int? _confidence;                    // result from ML model (0-100)
```

**On app open (`initState`):**

```dart
void initState() {
  super.initState();
  MLService().initializeModels(); // loads TFLite models into memory NOW
                                  // so there's no delay when capture starts
}
```

> **Why pre-load?** TFLite models are large (8-12 MB). Loading them takes 1-3 seconds. By loading at screen open instead of at capture time, the user never waits.

**Navigation logic — how screens connect:**

Each child screen does NOT navigate itself. It calls a callback like `onModeSelected`. The main screen receives the callback and updates `_currentScreen`:

```dart
void _setModeAndNavigate(AppMode mode) {
  setState(() {
    _mode = mode;
    _currentScreen = ScreenState.capture; // switch to camera screen
  });
}

void _onCapture(int confidence) {
  setState(() {
    _confidence = confidence;   // save the ML result
    _currentScreen = ScreenState.diagnosis; // switch to results screen
  });
}
```

**Back button logic:**

The back button is intercepted to go "up" the flow, not to the previous Navigator route:

```dart
void _handleBack() {
  setState(() {
    switch (_currentScreen) {
      case ScreenState.modeSelection:   _currentScreen = ScreenState.languageSelection;
      case ScreenState.capture:         _currentScreen = ScreenState.modeSelection;
      case ScreenState.diagnosis:       _currentScreen = ScreenState.capture;
      case ScreenState.geometricTool:   _currentScreen = ScreenState.diagnosis;
      default: Navigator.of(context).pop(); // exit to dashboard
    }
  });
}
```

**Language toggle in AppBar:**

After language selection, the AppBar shows a toggle button (EN | සිං). Pressing it instantly switches all text in all child screens because `_language` is passed as a prop.

**Animated screen transitions:**

```dart
body: AnimatedSwitcher(
  duration: const Duration(milliseconds: 300),
  child: _buildCurrentScreen(), // swaps with a fade animation
),
```

---

### 5.2 LanguageSelectionScreen

**File:** [language_selection_screen.dart](my_flutter_app/lib/screens/ar_capture/language_selection_screen.dart)

The entry point. Shows two large buttons: **English** and **සිංහල (Sinhala)**.

When pressed, calls `onLanguageSelected(AppLanguage.en)` or `onLanguageSelected(AppLanguage.si)`. The main screen stores the choice and moves to mode selection. All subsequent screens receive the language as a prop and display translated text.

---

### 5.3 ModeSelectionScreen

**File:** [mode_selection_screen.dart](my_flutter_app/lib/screens/ar_capture/mode_selection_screen.dart)

Two option cards:
- **Head Analysis** — cranial asymmetry screening
- **Posture Analysis** — body posture asymmetry screening

Each card shows an icon, title, description, and a start button. Pressing either calls `onModeSelected(AppMode.head)` or `onModeSelected(AppMode.posture)`.

The footer shows: `v1.0.0 - Offline Mode` — indicating ML inference works without internet.

---

### 5.4 ChildDetailsScreen

**File:** [child_details_screen.dart](my_flutter_app/lib/screens/ar_capture/child_details_screen.dart)

A form that collects:
- Child's name (required)
- Child's age (required)

Returns a `ChildDetailsData` object with these two fields. This data is attached to the report saved in Firebase so the midwife knows which child the scan belongs to.

---

### 5.5 HowToScanScreen

**File:** [how_to_scan_screen.dart](my_flutter_app/lib/screens/ar_capture/how_to_scan_screen.dart)

Shows 3 instruction steps for the chosen mode. Each step has an icon, a number badge, and guidance text.

| Head mode steps | Posture mode steps |
|---|---|
| 1. Position baby face-on | 1. Stand baby upright |
| 2. Ensure full head is visible | 2. Align body to vertical guide |
| 3. Keep camera level | 3. Capture full body in frame |

Both EN and Sinhala versions are fully supported.

---

### 5.6 HeadCaptureScreen

**File:** [head_capture_screen.dart](my_flutter_app/lib/screens/ar_capture/head_capture_screen.dart)

This screen captures the head image and runs the ML model.

**UI layout (Stack-based):**

```
┌──────────────────────────────────┐
│  Title: "Head Analysis Capture"  │  ← black overlay at top
│  Instruction text                │
├──────────────────────────────────┤
│                                  │
│   Live Camera Preview            │
│   (with oval alignment guide)    │  ← CameraView widget fills screen
│                                  │
├──────────────────────────────────┤
│  [📷 Shutter]  [🖼 Gallery]      │  ← buttons at bottom
└──────────────────────────────────┘
```

**Image capture flow:**

```dart
// Native (Android/iOS):
void _handleCameraCapture() async {
  final xFile = await _cameraKey.currentState?.takePicture(); // uses CameraController
  if (xFile != null) {
    await _processImage(xFile.path); // local file path e.g. /data/.../image.jpg
  }
}

// Gallery fallback:
void _handleGalleryPicker() async {
  final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
  if (image != null) {
    await _processImage(image.path);
  }
}
```

**Processing pipeline:**

```dart
Future<void> _processImage(String imagePath) async {
  // 1. Validate path is not empty/null
  if (imagePath.isEmpty) { show error snackbar; return; }

  // 2. Show loading spinner
  setState(() => _isProcessing = true);

  // 3. Run ML model - this is the heavy work
  int confidence = await MLService().runInference(imagePath, AppMode.head);

  // 4. Hand result up to ARCaptureMainScreen
  widget.onCapture(confidence); // triggers navigation to DiagnosisScreen
}
```

While `_isProcessing = true`, the bottom buttons are replaced with:
```
⬤ Analyzing AI Model...
```
(a circular progress indicator with text)

---

### 5.7 PostureCaptureScreen

**File:** [posture_capture_screen.dart](my_flutter_app/lib/screens/ar_capture/posture_capture_screen.dart)

Same structure as HeadCaptureScreen but:
- Shows a **vertical center line** guide instead of an oval (to help align body midline)
- Calls `MLService().runInference(imagePath, AppMode.posture)`
- Instruction text is posture-specific

---

### 5.8 DiagnosisScreen

**File:** [diagnosis_screen.dart](my_flutter_app/lib/screens/ar_capture/diagnosis_screen.dart)

Shows the ML result as a traffic light and gives the midwife action options.

**Score to colour mapping:**

```dart
// confidence is 0-100 (from MLService)
Color getResultColor(int confidence) {
  if (confidence <= 40) return Colors.green;   // Normal
  if (confidence <= 80) return Colors.amber;   // Inconclusive
  return Colors.red;                           // Abnormal
}
```

**Actions depending on result:**

| Score range | Label | Available actions |
|---|---|---|
| 0 – 40 | Normal | **Save & Finish** → writes to Firebase |
| 40 – 80 | Inconclusive | **Retake** (forced — must try again) |
| 80 – 100 (Head) | Abnormal | **Retake** or **Go Home** |
| 80 – 100 (Posture) | Abnormal | **Open Geometric Tool** or **Retake** |

**Save & Finish flow:**

When the midwife taps Save, the screen calls `ChildReportService.addReport()` with the full result. This writes to Firestore. See [Section 8](#8-firebase-setup--integration) for details.

---

### 5.9 GeometricToolScreen

**File:** [geometric_tool_screen.dart](my_flutter_app/lib/screens/ar_capture/geometric_tool_screen.dart)

Only shown for abnormal posture results. Lets the midwife manually verify measurements by displaying:
- Shoulder tilt angle (with visual rotation transform)
- Hip alignment angle (with visual rotation transform)
- A deviation warning when angles exceed safe thresholds

Has a **Confirm** button that triggers `onConfirm` (goes back to DiagnosisScreen).

---

### 5.10 ARReportsListScreen

**File:** [ar_reports_list_screen.dart](my_flutter_app/lib/screens/ar_capture/ar_reports_list_screen.dart)

Route: `/child-reports`

Lists all past scans saved in Firebase for the logged-in midwife.

**Load sequence:**

```dart
void initState() {
  super.initState();
  _loadReports(); // called once on screen open
}

Future<void> _loadReports() async {
  setState(() => _loading = true);
  final reports = await ChildReportService.getReports(); // reads Firestore
  setState(() { _reports = reports; _loading = false; });
}
```

**Each report card shows:**
- Mode icon (head 👶 or posture 🧍)
- Child name and age
- Date of scan
- Summary text
- Risk badge:
  - 🟢 **Low Risk** — normal result
  - 🟡 **Review** — inconclusive, needs follow-up
  - 🔴 **High Priority** — abnormal, refer to doctor
  - ⚪ **Unavailable** — scan failed

A pull-to-refresh button re-runs `_loadReports()`.

---

## 6. Widgets

### 6.1 CameraView Widget

**File:** [camera_view.dart](my_flutter_app/lib/widgets/ar_capture/camera_view.dart)

This widget handles the actual camera preview and AR overlay. It behaves differently on Web vs Native:

**Native (Android/iOS):**

```dart
// Uses the camera package
CameraController _controller = CameraController(
  cameras.first,
  ResolutionPreset.high, // high-res capture
);
await _controller.initialize();

// Expose takePicture() to parent via GlobalKey
Future<XFile?> takePicture() async {
  return await _controller.takePicture();
}
```

**Web:**

```dart
// Uses image_picker (no CameraController on web)
// When user picks a file, reads it as a data URL (base64)
// Calls onImageCaptured(dataUrl) directly back to HeadCaptureScreen
```

**AR Alignment Overlay:**

The camera preview has a `CustomPaint` layer drawn on top using `GuidelinePainter`:

```dart
// Head mode: draws a centered oval
// Width 250px, Height 350px — sized for infant head
canvas.drawOval(Rect.fromCenter(...), paint);

// Posture mode: draws a vertical center line
canvas.drawLine(
  Offset(size.width / 2, 0),
  Offset(size.width / 2, size.height),
  paint,
);
```

These guides help the midwife position the baby correctly before capturing.

---

## 7. ML & AI Services

### 7.1 MLService — TFLite Inference Engine

**File:** [ml_service.dart](my_flutter_app/lib/services/ar_capture/ml_service.dart)

This is the **core AI engine**. It is a **singleton** — only one instance exists in memory no matter how many times you call `MLService()`.

```dart
static final MLService _instance = MLService._internal();
factory MLService() => _instance; // always returns the same object
```

#### Model Loading

```dart
Future<void> initializeModels() async {
  // Loads the two TFLite models from the app's asset bundle into memory
  _headInterpreter    = await Interpreter.fromAsset('assets/models/cranial_analysis.tflite');
  _postureInterpreter = await Interpreter.fromAsset('assets/models/posture_analysis.tflite');
}
```

> On Web: skips loading (uses a web-specific code path instead).

#### Full Inference Pipeline (Step by Step)

```dart
Future<int> runInference(String imagePath, AppMode mode) async {

  // STEP 1: Path validation
  // Reject empty, "null", or "undefined" paths immediately
  if (imagePath.isEmpty || imagePath == 'null') return 0;

  // STEP 2: Platform check
  if (kIsWeb) return await _runWebInference(imagePath, mode); // different code path

  // STEP 3: Pick the right model
  final interpreter = mode == AppMode.head ? _headInterpreter : _postureInterpreter;

  // STEP 4: Read image file from disk
  final file = File(imagePath);
  if (!await file.exists()) return 0;   // file missing → return 0
  final imageBytes = await file.readAsBytes();
  if (imageBytes.isEmpty) return 0;      // empty file → return 0

  // STEP 5: Decode image (JPEG/PNG → pixel array)
  img.Image? decodedImage = img.decodeImage(imageBytes);
  if (decodedImage == null) return 0;

  // STEP 6: Optional validation
  // bypassValidation = true (default for testing) skips the skin-tone check
  final isValid = bypassValidation || _validateBabyImage(decodedImage, mode);
  if (!isValid) return 0;

  // STEP 7: Read model's expected input shape
  // e.g. [1, 224, 224, 3] means: 1 image, 224px high, 224px wide, 3 colour channels
  final inputShape = interpreter.getInputTensor(0).shape;
  final int modelHeight = inputShape[1]; // 224
  final int modelWidth  = inputShape[2]; // 224

  // STEP 8: Resize image to match model input
  img.Image resizedImage = img.copyResize(decodedImage,
    width: modelWidth, height: modelHeight);

  // STEP 9: Convert pixels to tensor format
  // Each pixel becomes [R/255, G/255, B/255] (float32 normalised 0.0–1.0)
  var input = List.generate(1,
    (_) => List.generate(modelHeight,
      (y) => List.generate(modelWidth,
        (x) {
          final pixel = resizedImage.getPixel(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        })));

  // STEP 10: Prepare output buffer
  // For a 2-class model: output[0] = [normalProbability, abnormalProbability]
  var output = List<List<double>>.generate(1, (_) => List<double>.filled(2, 0.0));

  // STEP 11: RUN THE MODEL
  interpreter.run(input, output);
  // output[0][0] = probability of NORMAL (e.g. 0.3 = 30%)
  // output[0][1] = probability of ABNORMAL (e.g. 0.7 = 70%)

  // STEP 12: Extract abnormal confidence and convert to 0-100
  double confidenceValue = output[0][1]; // use the "abnormal" class
  int result = (confidenceValue * 100).round().clamp(0, 100);
  // e.g. 0.73 → 73%

  return result;
}
```

#### Baby Image Validation

When `bypassValidation = false`, the service checks whether the image actually looks like a baby before running the expensive ML model. This prevents false results from random photos.

```dart
bool _validateBabyImage(img.Image image, AppMode mode) {

  // Check 1: Aspect ratio must be between 0.5 and 2.0
  // (rejects ultra-wide or ultra-tall images)
  final imageRatio = image.width / image.height;
  if (imageRatio < 0.5 || imageRatio > 2.0) return false;

  // Check 2: Skin tone must cover ≥ 35% of the image
  // (detects human skin — light, medium, and dark tones supported)
  final skinToneRatio = _calculateSkinToneRatio(image);
  if (skinToneRatio < 0.35) return false;

  // Check 3: Brightness must be between 0.2 and 0.9
  // (rejects too-dark or over-exposed photos)
  final brightness = _calculateAverageBrightness(image);
  if (brightness < 0.2 || brightness > 0.9) return false;

  // Check 4a: Head mode — centre of image must have ≥ 45% skin
  // (confirms face is centred in frame)
  if (mode == AppMode.head) {
    if (_getCentralSkinRatio(image) < 0.45) return false;
  }

  // Check 4b: Posture mode — at least 30% skin overall
  if (mode == AppMode.posture) {
    if (_calculateSkinToneRatio(image) < 0.30) return false;
  }

  return true; // passed all checks
}
```

**Skin tone detection formula** (3 ranges covering all skin tones):

```dart
// Light skin
if (r > 0.4 && g > 0.32 && b > 0.25 && r > g*1.15 && r > b*1.4 && g > b*1.2)

// Medium skin
if (r > 0.35 && g > 0.27 && b > 0.2 && r > g*1.2 && r > b*1.5)

// Darker skin
if (r > 0.3 && g > 0.22 && b > 0.15 && r > g*1.25 && r > b*1.7)
```

The pattern: **red channel is always highest**, then green, then blue — which describes the reddish-brown tones of human skin.

---

### 7.2 CranialAnalysisService — Head Screening

**File:** [cranial_analysis_service.dart](my_flutter_app/lib/services/ar_capture/cranial_analysis_service.dart)

This service runs the detailed head analysis pipeline after image capture. It works in 3 stages:

**Stage 1 — Landmark Detection:**

```
Try MediaPipe Face Landmarker (native Android via method channel)
        │
        ▼ (if MediaPipe unavailable or fails)
Try Google ML Kit FaceMeshDetector (fallback)
        │
        ▼ (extracts 468 facial landmarks)
HeadLandmarkerRuntime → normalized x,y,z coordinates for each point
```

**Stage 2 — Geometry Analysis:**

Using landmark positions, the service calculates:
- **Cranial Index** = (head width / head length) × 100
  - Normal: 75–85. Below = dolichocephaly. Above = brachycephaly.
- **CVAI (Cranial Vault Asymmetry Index)** = |diagonal1 - diagonal2| / shorter diagonal × 100
  - Normal: < 3.5%. Above 6.25% = significant asymmetry.
- **Facial Symmetry Offset** = (left side width − right side width) / total face width × 100
- **Temple Tilt** = angle of line connecting left and right temples (degrees from horizontal)

**Stage 3 — AI Assessment (Gemini):**

If the Gemini API key is available, the service sends:
- The actual image (base64 encoded, up to 896px)
- The geometry measurements as JSON
- A detailed medical system prompt

Gemini returns a structured analysis with risk level, head shape classification, and clinical recommendations.

**Image size optimization:**

```dart
// Large images are downscaled before processing to save memory
// Images > 1MB are resized to max 1024px on longest edge
if (imageBytes.length > 1_000_000) {
  image = img.copyResize(image, width: 1024);
}
```

---

### 7.3 HeadLandmarkerRuntime — MediaPipe Bridge

**File:** [head_landmarker_runtime.dart](my_flutter_app/lib/services/ar_capture/head_landmarker_runtime.dart)

This is the bridge between Flutter (Dart) and the native Android code that runs MediaPipe.

```dart
// Flutter side: sends the image path to Android
static const _channel = MethodChannel('midwify/head_landmarker');

static Future<HeadLandmarkerRuntimeResult?> detect(String imagePath) async {
  if (!Platform.isAndroid) return null; // only works on Android

  final result = await _channel.invokeMethod('detectFromPath', {
    'imagePath': imagePath,
  });
  // result is a Map with landmarks, source, warnings
  return HeadLandmarkerRuntimeResult.fromMap(result);
}
```

The native Android code (Kotlin/Java) receives this call, loads the `face_landmarker.task` MediaPipe model, runs it on the image, and returns 468 3D facial landmark coordinates back to Flutter.

**Why a method channel?** MediaPipe's native SDK doesn't have a Flutter plugin, so the code must run natively and communicate via platform channels.

---

### 7.4 CranialMetrics — Geometry Math

**File:** [cranial_metrics.dart](my_flutter_app/lib/services/ar_capture/cranial_metrics.dart)

Pure math functions used by CranialAnalysisService. Key classes and constants:

```dart
class Landmark3D {
  final double x, y, z; // normalized 0.0-1.0 coordinates
}

class CranialResult {
  final double cranialIndex;
  final double cvai;               // Cranial Vault Asymmetry Index
  final double facialSymmetryOffset;
  final double templeTiltDeg;
  final double landmarkQuality;
  final RiskBand riskBand;
  ...
}

// Thresholds for flagging problems
const kMaxTempleTiltDeg    = 12.0;  // head tilt > 12° = likely bad camera angle
const kMaxForeheadSkewPct  = 12.0;  // forehead asymmetry > 12% = review
const kMinAngleZDiff       = 0.005; // minimum depth difference for 3D validation
```

**Distance calculation (2D):**

```dart
double distance2D(Landmark3D a, Landmark3D b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return sqrt(dx*dx + dy*dy);
}
```

**Risk mapping:**

```
Cranial Index:   75–85   → lowRisk
                 85–90   → review
                 > 90    → refer
CVAI:            < 3.5   → lowRisk
                 3.5–6.25 → review
                 > 6.25  → refer
```

---

### 7.5 PostureScreeningService — Body Analysis

**File:** [posture_screening.dart](my_flutter_app/lib/services/ar_capture/posture_screening.dart)

Analyses body pose for postural asymmetry.

**Input:** 13 keypoint coordinates from a pose estimation model:
- Left/right shoulder, elbow, wrist, hip, knee, ankle
- Head/neck position

**Measurements calculated:**

```dart
// Shoulder tilt: angle of line connecting both shoulders
double shoulderTilt = atan2(
  rightShoulder.y - leftShoulder.y,
  rightShoulder.x - leftShoulder.x
) * (180 / pi);

// Hip tilt: same method for hips
// Trunk tilt: midpoint-of-shoulders to midpoint-of-hips line angle
// Head tilt: head position relative to trunk midline
// Midline offset: how far the body's centre is from frame centre
```

**Risk scoring:**

```
Score = weighted combination of all tilt values
Score < 35  → lowRisk  (normal posture)
Score 35–70 → review   (mild asymmetry)
Score > 70  → refer    (significant asymmetry)
```

**Quality validation:**

The service checks visibility scores for each keypoint. If key joints are not visible (e.g. body cut off at edges), it adds warnings and may reject the scan:

```
"Left shoulder not visible — ensure full torso is in frame"
"Hips not detected — stand baby further from camera"
```

---

### 7.6 GeminiCranioService — AI Visual Analysis

**File:** [gemini_cranio_service.dart](my_flutter_app/lib/services/ar_capture/gemini_cranio_service.dart)

An optional but powerful enhancement. Uses Google's **Gemini 2.5 Flash** multimodal model to visually assess head shape.

**How it works:**

```
Image (base64) ──┐
                 ├──► HTTP POST to Gemini API ──► Structured JSON response
Geometry JSON ───┘
```

**API call:**

```dart
// Endpoint
final url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

// Request body
{
  "system_instruction": { "parts": [{ "text": "<498-line medical prompt>" }] },
  "contents": [{
    "parts": [
      { "inline_data": { "mime_type": "image/jpeg", "data": "<base64>" }},
      { "text": "Geometry measurements: { cranialIndex: 85.2, cvai: 4.1, ... }" }
    ]
  }],
  "generation_config": { "response_mime_type": "application/json" }
}
```

**Response structure:**

```json
{
  "riskLevel": "moderate",
  "riskScore": 58,
  "headShapeClassification": "mild plagiocephaly",
  "confidence": "medium",
  "urgency": "soon",
  "keyFindings": ["Slight flattening on right posterior", "Mild forehead asymmetry"],
  "visualObservations": "The photo shows visible flattening on the right occipital region...",
  "recommendation": "Refer to paediatric physiotherapy within 4 weeks"
}
```

**Configuration:**

```bash
# app.env
GEMINI_API_KEY=your_key_here
```

```dart
// Loaded at runtime
final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
```

**Timeout:** 35 seconds. If Gemini doesn't respond in time, the service falls back to geometry-only scoring.

**Image size handling:** Images are resized to max 896px before being sent to Gemini to stay within API limits.

---

### 7.7 ClassifierService — Binary Output

**File:** [classifier_service.dart](my_flutter_app/lib/services/ar_capture/classifier_service.dart)

A simple wrapper that maps a raw confidence score to a human-readable status:

```dart
// Logic
if (score < 40) → status: "Normal",  color: green,  message: "No concerns found"
if (score < 80) → status: "Uncertain", color: amber, message: "Further assessment needed"
else            → status: "Abnormal", color: red,   message: "Refer for clinical review"
```

This service references `models/head_shape.tflite` in its original design but the main inference currently runs through `MLService` using `cranial_analysis.tflite`.

---

### 7.8 ScanReportLogger — Local Logging

**File:** [scan_report_logger.dart](my_flutter_app/lib/services/ar_capture/scan_report_logger.dart)

Saves a complete JSON log of every scan to the device's documents directory. Useful for debugging and research.

```dart
// File saved as:
// <appDocumentsDir>/scan_logs/scan_head_1714234567890.json
// <appDocumentsDir>/scan_logs/scan_posture_1714234600000.json

// Content: full ARCaptureResult.toJson() output
```

Also prints to the debug console with the prefix `AR_SCAN_REPORT` for easy filtering in Android Studio / VS Code.

> On Web: file writing is skipped (no local filesystem access).

---

## 8. Firebase Setup & Integration

### 8.1 Project Configuration

**File:** [firebase_options.dart](my_flutter_app/lib/firebase_options.dart)

Firebase project: **`midwify-3f933`**

| Setting | Value |
|---|---|
| Project ID | `midwify-3f933` |
| Storage bucket | `midwify-3f933.firebasestorage.app` |
| Auth domain | `midwify-3f933.firebaseapp.com` |
| Messaging sender ID | `203322719348` |
| Location | `nam5` (North America multi-region) |

**Initialisation in main.dart:**

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // reads firebase_options.dart
  );
  runApp(const MyApp());
}
```

This must run before any Firebase service is used.

**Packages used:**

```yaml
firebase_core: ^3.12.1       # must always be included
firebase_auth: ^5.5.1         # user authentication
cloud_firestore: ^5.6.5       # database
```

---

### 8.2 Authentication Flow

Before any Firestore read or write, the user must be signed in. The authenticated user's UID is used as the Firestore document ID, which means each midwife has their own private data.

```dart
// Get the current user's UID
String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

// If empty, no one is signed in — abort
if (uid.isEmpty) throw Exception('No authenticated user found');
```

The app uses email/password authentication on the Login screen. Once signed in, `currentUser` stays populated for the entire session.

---

### 8.3 Firestore Data Structure

All report data is stored in a **single document per midwife**:

```
Firestore Database
└── midwives/                          ← collection
    └── {midwifeUID}/                  ← document (one per midwife)
        ├── name: "Dilani Perera"
        ├── email: "dilani@health.lk"
        └── child_reports: [           ← array of report maps
              {
                "id": "1714234567890",
                "childName": "Baby Amaya",
                "childAge": "3 months",
                "mode": "head",
                "midwifeId": "abc123uid",
                "createdAt": Timestamp(2024-04-27T10:30:00Z),
                "result": {
                  "isValidImage": true,
                  "supportedView": true,
                  "qualityScore": 82,
                  "screeningScore": 34,
                  "riskBand": "lowRisk",
                  "summary": "Head shape within normal range",
                  "warnings": [],
                  "headMetrics": {
                    "cranialIndex": 78.5,
                    "cranialVaultAsymmetryIndex": 2.1,
                    "facialSymmetryOffsetPct": 3.8,
                    ...
                  }
                }
              },
              { ... next report ... }
            ]
```

> **Design choice:** Using an **array field** (`child_reports`) instead of a sub-collection means the entire midwife's report history is read in a **single Firestore read** — efficient and low-cost.

---

### 8.4 ChildReportService — Reading & Writing Reports

**File:** [child_report_service.dart](my_flutter_app/lib/services/child_report_service.dart)

#### Saving a Report (Write)

```dart
static Future<String> addReport(ChildReportData report) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) throw Exception('No authenticated user found');

  final docRef = FirebaseFirestore.instance
      .collection('midwives')
      .doc(uid);                    // e.g. "midwives/abc123uid"

  await docRef.update({
    'child_reports': FieldValue.arrayUnion([report.toMap()])
    //                ^^^^^^^^^^^^^^^^^^^
    // arrayUnion appends the new report to the existing array
    // without overwriting anything else in the document
  });

  return report.id; // return the generated report ID
}
```

> **Why `update()` and not `set(merge: true)`?** Firestore security rules are typically written to only allow `update` on existing midwife documents (not `set`). Using `update()` ensures the security rules fire correctly and prevents creating phantom documents for non-authenticated users.

#### Reading Reports (Read)

```dart
static Future<List<ChildReportData>> getReports() async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) return [];       // not logged in → return empty list

  // 1. Fetch the midwife's document
  final doc = await FirebaseFirestore.instance
      .collection('midwives')
      .doc(uid)
      .get();

  if (!doc.exists) return [];       // no document yet → return empty list

  // 2. Extract the child_reports array
  final data = doc.data();
  if (data == null || !data.containsKey('child_reports')) return [];

  final List<dynamic> rawList = data['child_reports'];

  // 3. Parse each map back into a ChildReportData object
  final reports = rawList
      .map((e) => ChildReportData.fromMap('extracted_id', e))
      .toList();

  // 4. Sort newest first (by Firestore Timestamp)
  reports.sort((a, b) {
    final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime); // descending: newest at index 0
  });

  return reports;
}
```

#### ChildReportData Serialisation

The `toMap()` method converts the Dart object to a plain Dart Map so Firestore can store it:

```dart
Map<String, dynamic> toMap() {
  return {
    'id':        id ?? DateTime.now().millisecondsSinceEpoch.toString(),
    'childName': childName,
    'childAge':  childAge,
    'mode':      mode,           // "head" or "posture"
    'midwifeId': midwifeId,
    'result':    result.toJson(), // recursive — ARCaptureResult → Map
    'createdAt': createdAt ?? Timestamp.now(),
  };
}
```

The `fromMap()` factory does the reverse — reads a raw Firestore Map and reconstructs the nested objects:

```dart
factory ChildReportData.fromMap(String id, Map<String, dynamic> map) {
  // Parse headMetrics from the nested result.headMetrics map
  HeadScreeningMetrics? hMetrics;
  if (map['result']?['headMetrics'] != null) {
    final hm = map['result']['headMetrics'];
    hMetrics = HeadScreeningMetrics(
      cranialIndex: (hm['cranialIndex'] ?? 0).toDouble(),
      ...
    );
  }

  // Parse riskBand string back to enum
  final riskBandStr = map['result']?['riskBand'] ?? 'unavailable';
  RiskBand rBand = RiskBand.unavailable;
  if (riskBandStr == 'lowRisk') rBand = RiskBand.lowRisk;
  if (riskBandStr == 'review')  rBand = RiskBand.review;
  if (riskBandStr == 'refer')   rBand = RiskBand.refer;

  ...
  return ChildReportData(...);
}
```

---

### 8.5 Firestore Security Rules

**File:** [firestore.rules](my_flutter_app/firestore.rules)

The rules ensure a midwife can only read and update their own document:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /midwives/{midwifeId} {
      // Allow read if authenticated AND the document belongs to the current user
      allow read: if request.auth != null && request.auth.uid == midwifeId;

      // Allow update (array append) only — no set/create by the app
      allow update: if request.auth != null && request.auth.uid == midwifeId;
    }
  }
}
```

This means:
- A midwife cannot read another midwife's reports
- Only `update` is allowed (not `set`), matching what `addReport()` calls
- Unauthenticated users have no access at all

---

## 9. Assets & Dependencies

### ML Model Assets

| File | Size | Purpose |
|---|---|---|
| `cranial_analysis.tflite` | 8.87 MB | Classifies head images as normal/abnormal |
| `posture_analysis.tflite` | 12.58 MB | Classifies posture images as normal/abnormal |
| `face_landmarker.task` | 3.76 MB | MediaPipe model for extracting 468 face landmarks |

All three are bundled inside the app (in `assets/models/`) and work completely offline.

### Key pubspec.yaml Dependencies

```yaml
# Firebase
firebase_core: ^3.12.1
firebase_auth: ^5.5.1
cloud_firestore: ^5.6.5

# Camera & Images
camera: ^0.11.0+1
image_picker: 1.1.2
image: ^4.1.3            # image decoding and resizing in Dart

# Machine Learning
tflite_flutter: ^0.12.1  # runs TFLite models on device
google_mlkit_face_mesh_detection: ^0.4.2  # fallback face landmarks

# Utilities
permission_handler: ^11.3.1  # camera permission prompts
flutter_dotenv: ^5.2.1       # loads app.env for API keys
http: ^1.2.1                 # HTTP calls to Gemini API
intl: ^0.19.0                # date/number formatting
```

---

## 10. End-to-End Worked Example

This traces exactly what happens when a midwife runs a **Head Analysis** scan from start to finish.

```
1. Midwife opens /ar-capture
   └─ ARCaptureMainScreen.initState()
      └─ MLService().initializeModels()
         ├─ Loads cranial_analysis.tflite (8.87 MB) into _headInterpreter
         └─ Loads posture_analysis.tflite (12.58 MB) into _postureInterpreter

2. LanguageSelectionScreen appears
   └─ Midwife taps "English"
      └─ _language = AppLanguage.en
      └─ _currentScreen = ScreenState.modeSelection

3. ModeSelectionScreen appears
   └─ Midwife taps "Head Analysis"
      └─ _mode = AppMode.head
      └─ _currentScreen = ScreenState.capture

4. HeadCaptureScreen appears
   └─ CameraView initialises CameraController (high resolution)
   └─ Oval AR guide drawn on camera preview
   └─ Midwife aligns baby's head inside oval
   └─ Midwife taps shutter button

5. _handleCameraCapture() runs
   └─ _controller.takePicture()
      └─ Saves image to /data/data/.../cache/image_1714234567.jpg
   └─ _processImage("/data/.../image_1714234567.jpg") called

6. _processImage() validates path → not empty ✓
   └─ setState(_isProcessing = true)  → spinner shown
   └─ MLService().runInference("/data/.../image.jpg", AppMode.head) called

7. MLService.runInference():
   Step 1: path not empty ✓
   Step 2: not web ✓
   Step 3: uses _headInterpreter
   Step 4: reads file → 1.2 MB image bytes
   Step 5: decodes JPEG → img.Image (3000×4000px)
   Step 6: bypassValidation=true → skip skin check
   Step 7: model expects [1, 224, 224, 3]
   Step 8: resize image to 224×224px
   Step 9: convert to float tensor [[[R,G,B]×224]×224]×1]
   Step 10: output buffer = [[0.0, 0.0]]
   Step 11: interpreter.run(input, output)
            → output = [[0.31, 0.69]]
              (31% normal, 69% abnormal)
   Step 12: confidencePercentage = (0.69 × 100).round() = 69

8. Back in HeadCaptureScreen:
   └─ confidence = 69
   └─ widget.onCapture(69) called
   └─ setState(_isProcessing = false) → spinner hidden

9. ARCaptureMainScreen._onCapture(69):
   └─ _confidence = 69
   └─ _currentScreen = ScreenState.diagnosis

10. DiagnosisScreen appears with confidence=69
    └─ 69 is in 40-80 range → Amber "Inconclusive"
    └─ Shows "Retake" button only (no Save option)
    └─ Midwife taps Retake
       └─ _currentScreen = ScreenState.capture

11. Midwife captures again → confidence = 28 (normal result)

12. DiagnosisScreen shows Green "Normal"
    └─ Midwife taps "Save & Finish"
       └─ ChildReportService.addReport(ChildReportData {
            childName: "Baby Amaya",
            childAge:  "3 months",
            mode:      "head",
            result:    ARCaptureResult { screeningScore: 28, riskBand: lowRisk, ... }
          })
       └─ Firestore: midwives/abc123uid.child_reports.arrayUnion([...])
       └─ Report saved ✓

13. _navigateHome() → _currentScreen = ScreenState.modeSelection
    (ready for next scan)
```

---

## 11. Risk Band Reference

| Risk Band | Score Range | Colour | Label | Action |
|---|---|---|---|---|
| `lowRisk` | 0 – 40 | 🟢 Green | Normal | Save & complete |
| `review` | 40 – 80 | 🟡 Amber | Inconclusive | Retake required |
| `refer` | 80 – 100 | 🔴 Red | Abnormal | Refer to clinician |
| `unavailable` | N/A | ⚪ Grey | Scan failed | Try again |

**CVAI thresholds (head-specific):**

| CVAI value | Classification | Risk band |
|---|---|---|
| < 3.5% | Normal asymmetry | lowRisk |
| 3.5 – 6.25% | Mild asymmetry | review |
| > 6.25% | Significant asymmetry | refer |

**Posture tilt thresholds:**

| Screening score | Classification | Risk band |
|---|---|---|
| < 35 | Normal posture | lowRisk |
| 35 – 70 | Mild asymmetry | review |
| > 70 | Significant asymmetry | refer |

---

## 12. Bilingual Support (EN / සිං)

Every screen accepts `AppLanguage language` as a parameter. Inside each screen, a translation map is defined at build time:

```dart
final t = {
  AppLanguage.en: {
    'title': 'Head Analysis Capture',
    'instruction': "Align the guide with the baby's features",
    'processing': 'Analyzing AI Model...',
  },
  AppLanguage.si: {
    'title': 'හිස විශ්ලේෂණ ඡායාරූපය',
    'instruction': 'මාර්ගෝපදේශය ළදරුවාගේ ලක්ෂණ සමඟ පෙළගස්වා...',
    'processing': 'AI ආකෘතිය විශ්ලේෂණය කරමින්...',
  }
}[widget.language]!; // looks up the right language map

// Then used as:
Text(t['title']!)
```

The language is stored in `ARCaptureMainScreen._language` and propagated down via props. The AppBar language toggle button (`EN | සිං`) calls `_setLanguage()` which triggers a `setState`, causing all child screens to rebuild with the new language instantly.

---

## 13. Platform Differences

| Feature | Android | iOS | Web |
|---|---|---|---|
| TFLite inference | ✅ Full | ✅ Full | ⚠️ Mock only |
| MediaPipe landmarks | ✅ via method channel | ❌ Not supported | ❌ Not supported |
| ML Kit face mesh | ✅ Supported | ✅ Supported | ❌ Not supported |
| Camera preview | ✅ CameraController | ✅ CameraController | ⚠️ image_picker only |
| Local file access | ✅ Full | ✅ Full | ❌ Data URL only |
| Gemini AI | ✅ HTTP call | ✅ HTTP call | ✅ HTTP call |
| Firebase | ✅ Full | ✅ Full | ✅ Full |
| Scan log files | ✅ Saved to disk | ✅ Saved to disk | ❌ Skipped |

> **Testing tip:** Set `MLService.bypassValidation = true` (it is `true` by default) to skip the skin-tone check when testing with non-baby images or in a development environment.
