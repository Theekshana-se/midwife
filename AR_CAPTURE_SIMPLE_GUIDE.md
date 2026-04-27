# AR Capture — Simple Teaching Guide

> This guide is written for someone learning the project for the first time.
> No deep coding knowledge needed. We explain **what happens, why it happens, and how the code does it** — in plain language.

---

## Part 1 — What Does AR Capture Do?

Imagine a community midwife visiting a family with a newborn baby. She opens the app, points the phone camera at the baby, and the app tells her:

- Is the baby's **head shape** normal or abnormal?
- Is the baby's **body posture** balanced or unbalanced?

The app uses **AI (Artificial Intelligence)** to analyse the photo and give a result. The result is saved to the cloud so a doctor can check it later.

That is the whole idea. Everything in the code exists to make that happen safely and correctly.

---

## Part 2 — The Two Scan Types

The app has two modes:

```
┌─────────────────────────────────────────────────────────┐
│  HEAD ANALYSIS                                          │
│  Takes a photo of the baby's head (face-on view)        │
│  Checks: Is the skull symmetrical? Is the shape normal? │
│  Medical term: Screening for craniosynostosis /         │
│                plagiocephaly (flat head syndrome)       │
├─────────────────────────────────────────────────────────┤
│  POSTURE ANALYSIS                                       │
│  Takes a photo of the baby's full body (standing view)  │
│  Checks: Are the shoulders level? Are the hips even?    │
│  Medical term: Postural asymmetry screening             │
└─────────────────────────────────────────────────────────┘
```

Both modes go through the **same steps** — pick language → pick mode → take photo → get result → save report.

---

## Part 3 — The Journey of One Scan (Plain English)

Here is what happens from the moment the midwife opens the screen to when the report is saved:

```
Step 1:  Midwife opens the AR Capture screen
         → The app quietly loads the AI models into memory (so they are ready fast)

Step 2:  She picks a language (English or Sinhala)
         → The whole app switches language instantly

Step 3:  She picks a mode (Head or Posture)
         → The camera screen opens

Step 4:  The camera shows a live preview
         → A guide shape is drawn on screen (oval for head, vertical line for posture)
         → This helps her position the baby correctly

Step 5:  She taps the shutter button
         → The photo is saved as a file on the phone

Step 6:  The app sends the photo file to the AI model
         → The model reads every pixel of the photo
         → It outputs a number: 0 to 100
           (0 = definitely normal, 100 = definitely abnormal)

Step 7:  The result screen shows a traffic light
         → GREEN  (0–40)  = Normal — no concerns
         → AMBER  (40–80) = Inconclusive — try again
         → RED    (80–100)= Abnormal — refer to a doctor

Step 8:  If the result is Normal, she taps "Save & Finish"
         → The report is sent to Firebase (cloud database)
         → It is stored under her account

Step 9:  Later, the midwife or doctor can open the Reports screen
         → It fetches all saved reports from Firebase
         → Each report shows the child's name, age, date, and risk level
```

---

## Part 4 — How the Screens Are Connected

The most important thing to understand is that **one single screen controls everything**. It is called `ARCaptureMainScreen`.

Think of it like a TV remote control. The remote does not show anything itself — it just decides which channel (screen) to show.

```
ARCaptureMainScreen  ←  this is the "remote control"
        │
        │  It holds these values:
        │    currentScreen  = which screen to show right now
        │    mode           = head or posture
        │    language       = English or Sinhala
        │    confidence     = the AI result number (0–100)
        │
        ▼
  Shows ONE of these screens at a time:
  ┌──────────────────────┐
  │ Language Selection   │  → when done, tells the main screen "user picked English"
  ├──────────────────────┤
  │ Mode Selection       │  → when done, tells the main screen "user picked Head"
  ├──────────────────────┤
  │ Head Capture         │  → when done, tells the main screen "AI result is 34"
  │ (or Posture Capture) │
  ├──────────────────────┤
  │ Diagnosis (Result)   │  → when done, saves to Firebase and goes back to Mode
  ├──────────────────────┤
  │ Geometric Tool       │  → only shown for abnormal posture results
  └──────────────────────┘
```

**Key point:** Child screens never navigate themselves. They just call a function like `onCapture(confidence)` and the main screen decides what to do next.

**In code, this looks like:**

```dart
// Inside ARCaptureMainScreen
void _onCapture(int confidence) {
  setState(() {
    _confidence = confidence;          // save the AI result
    _currentScreen = ScreenState.diagnosis;  // switch to result screen
  });
}

// And it passes that function DOWN to the capture screen:
HeadCaptureScreen(
  onCapture: _onCapture,   // "when you're done, call this"
)
```

The child screen just calls `widget.onCapture(34)` and does not worry about what happens next.

---

## Part 5 — How the AI Model Works (Step by Step)

The AI part lives in one file: `ml_service.dart`. Here is exactly what it does with a photo:

```
Photo file on phone  (e.g. image.jpg, 3000×4000 pixels, 2MB)
         │
         ▼
Step 1: Read the file bytes from disk
         │
         ▼
Step 2: Decode the JPEG into a pixel grid
        (like opening the image in Paint — now we can read each pixel's colour)
         │
         ▼
Step 3: Resize to 224×224 pixels
        (the AI model only accepts images of this exact size)
         │
         ▼
Step 4: Convert each pixel to numbers
        Every pixel becomes three numbers: Red, Green, Blue
        Each number is divided by 255 to get a value between 0.0 and 1.0
        Example: a pink pixel → [0.95, 0.75, 0.80]
         │
         ▼
Step 5: Feed the numbers into the AI model
        The model is a TensorFlow Lite (.tflite) file
        It was trained by showing it thousands of baby photos labelled "normal" or "abnormal"
         │
         ▼
Step 6: The model outputs two numbers
        output[0] = probability of NORMAL   (e.g. 0.31 = 31%)
        output[1] = probability of ABNORMAL (e.g. 0.69 = 69%)
         │
         ▼
Step 7: We use the ABNORMAL number and multiply by 100
        0.69 × 100 = 69   ← this is the confidence score shown on screen
```

The two model files are bundled inside the app:
- `cranial_analysis.tflite` — used for head scans (8.87 MB)
- `posture_analysis.tflite` — used for posture scans (12.58 MB)

Because they are inside the app, **the phone does not need internet** to run the AI. Everything happens on-device.

---

## Part 6 — How Firebase Saves and Reads Reports

Firebase is Google's cloud service. The app uses two parts of it:

| Firebase service | What it does in this app |
|---|---|
| **Firebase Auth** | Handles login. Each midwife has a unique ID (UID). |
| **Cloud Firestore** | The database. Stores all scan reports. |

### How data is stored in Firestore

Think of Firestore like a folder system:

```
Database
└── midwives/               ← a folder called "midwives"
    └── abc123uid/          ← one folder per midwife (named after her UID)
        ├── name: "Dilani"
        ├── email: "dilani@health.lk"
        └── child_reports: [    ← a list of all her scan reports
              {
                childName: "Baby Amaya",
                childAge:  "3 months",
                mode:      "head",
                result: {
                  screeningScore: 28,
                  riskBand: "lowRisk",
                  summary: "Head shape within normal range"
                },
                createdAt: 27 April 2024
              },
              { ... next report ... },
              { ... next report ... }
            ]
```

Every midwife's reports are kept **separately** under her own UID. She cannot see another midwife's reports.

### Saving a report (Write)

```dart
// In child_report_service.dart
await docRef.update({
  'child_reports': FieldValue.arrayUnion([report.toMap()])
});
```

`arrayUnion` means: **add this new item to the list without touching the existing items**.

So if she already has 5 reports, this adds a 6th. It never deletes or overwrites the others.

### Reading reports (Read)

```dart
// In child_report_service.dart
final doc = await FirebaseFirestore.instance
    .collection('midwives')
    .doc(uid)     // only reads THIS midwife's document
    .get();

final rawList = doc.data()['child_reports']; // the list of all reports
```

After reading, the reports are **sorted newest first** so the most recent scan appears at the top of the list.

### Security

Firestore rules make sure:
- You can only read your own reports (not anyone else's)
- You must be logged in to do anything at all

```
// Simplified security rule:
allow read, update: if you are logged in AND it is your own document
```

---

## Part 7 — The Camera and the AR Guides

The camera screen (`camera_view.dart`) does two things at once:

1. Shows a live camera preview (what the lens sees)
2. Draws a guide shape on top of the preview

**Head mode** draws an oval:

```
┌────────────────────┐
│                    │
│      ╭─────╮       │  ← oval guide
│      │     │       │     midwife places baby's head inside this
│      ╰─────╯       │
│                    │
└────────────────────┘
```

**Posture mode** draws a vertical line:

```
┌────────────────────┐
│         │          │
│         │          │  ← centre line
│         │          │     midwife aligns baby's spine to this line
│         │          │
└────────────────────┘
```

These guides are drawn using Flutter's `CustomPaint` — a drawing canvas that sits on top of the camera preview. No actual AR technology is involved — it is just a helpful overlay drawn in code.

---

## Part 8 — The Gemini AI Extra Step (Head Mode Only)

For head analysis, there is an optional extra check using Google's **Gemini AI** (a powerful language + vision model).

After the basic measurements are calculated from face landmarks, the service can also send the photo directly to Gemini and ask:

> "Look at this baby photo. Here are the skull measurements. What is the risk level and what do you see?"

Gemini looks at the photo visually (like a doctor would) and replies with:

```json
{
  "riskLevel": "moderate",
  "riskScore": 58,
  "headShapeClassification": "mild plagiocephaly",
  "keyFindings": ["Slight flattening on right side", "Mild forehead asymmetry"],
  "recommendation": "Refer to physiotherapy within 4 weeks"
}
```

This is the only part of the app that **needs the internet**. If there is no internet (or no API key), the app falls back to geometry measurements only.

The API key is stored in a file called `app.env`:
```
GEMINI_API_KEY=your_key_here
```
This file is **never committed to Git** — it is kept private on the developer's machine.

---

## Part 9 — What Each File Does (Quick Reference)

| File | In simple words |
|---|---|
| `ar_capture_main_screen.dart` | The controller. Decides which screen to show. |
| `ar_capture_models.dart` | Defines all the data shapes (what a "result" looks like, what enums exist). |
| `language_selection_screen.dart` | The first screen — pick English or Sinhala. |
| `mode_selection_screen.dart` | Pick head scan or posture scan. |
| `head_capture_screen.dart` | Opens camera, captures head photo, runs AI. |
| `posture_capture_screen.dart` | Opens camera, captures body photo, runs AI. |
| `diagnosis_screen.dart` | Shows the traffic light result. Save or retake. |
| `geometric_tool_screen.dart` | Manual angle checker for abnormal posture results. |
| `ar_reports_list_screen.dart` | Shows history of all saved scans from Firebase. |
| `camera_view.dart` | The live camera preview widget with the guide overlays. |
| `ml_service.dart` | Runs the TFLite AI model on a photo and returns 0–100. |
| `cranial_analysis_service.dart` | Full head analysis pipeline (landmarks + geometry + Gemini). |
| `posture_screening.dart` | Full posture analysis pipeline (joint angles + scoring). |
| `gemini_cranio_service.dart` | Sends photo to Gemini AI and gets a detailed medical opinion. |
| `child_report_service.dart` | Saves and reads scan reports in Firebase Firestore. |
| `firebase_options.dart` | Firebase project credentials (which Firebase project to connect to). |

---

## Part 10 — Common Questions

**Q: Does the app need internet to scan?**
No. The AI models (`cranial_analysis.tflite` and `posture_analysis.tflite`) are inside the app. Scanning works fully offline. Only the Gemini AI extra check and saving to Firebase need internet.

**Q: What happens if the AI returns 0?**
Zero means something went wrong — the file was empty, the image could not be decoded, or the model was not loaded. The app shows an error or falls back gracefully.

**Q: Why is `bypassValidation = true`?**
There is a built-in check that tries to confirm the photo actually contains a baby (by checking skin tone ratios). During development and testing, this is turned off (`bypassValidation = true`) so developers can test with any photo. In production, this would be set to `false`.

**Q: Why use `arrayUnion` instead of just setting the whole list?**
Because `arrayUnion` is **safe for concurrent writes**. If two reports are saved at nearly the same time, `arrayUnion` adds both without either one overwriting the other. If you used `set()` with the full list, the second write would erase the first.

**Q: Where is the midwife's login ID used?**
The Firebase Auth UID (a unique random string like `"abc123uid"`) is used as the Firestore document name. This ties every scan report to the specific midwife who did it, and prevents any cross-reading of data.

**Q: What is a `RiskBand`?**
It is an enum (a fixed set of named values) with four options:
- `lowRisk` — normal result
- `review` — needs a follow-up scan
- `refer` — send to a doctor urgently
- `unavailable` — the scan failed and has no valid result

---

## Summary

The AR Capture feature is built around this simple loop:

```
Take photo  →  Run AI on photo  →  Show result  →  Save to Firebase
```

Everything else in the code exists to:
- Make the camera work correctly on different devices
- Make the AI model run fast and safely
- Make sure the result is stored securely for the right midwife
- Support both English and Sinhala languages
- Give the midwife clear guidance at every step
```

Think of it as a digital screening assistant that the midwife carries in her pocket.
