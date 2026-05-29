May 29, 2026 - 12:57pm - GitHub Copilot

# this file is for me to work out prompts for you. It is not cannonical rather insight into my process.

**_ Task _**
**_ Context _**
**_ Instructions _**
**_ Outcomes _**

**_ Task _**
Review the /promptercam-fixer project.

** context **
We are going to start making improvements to the original wireframe.
The Readme.md file explains the purpose of this project.
STYLING_GUIDE.md is a copy of styles from /Direct-Video-Uploader we need use to similar consistent approach styles for /promptercam-fixer. We should modify this STYLING_GUIDE.md specifically for /promptercam-fixer, one item of note is making all swift font sizes even numbers ie; font 10pt, 12pt etc.
.agents/skills/CLAUDE.md is a guide for coding.

** Instructions **
Show me a review of this project, then we will prepare a phased development plan.

** Current Known Issues **
This is currently a demo. I have compiled this in Xcode and reviewed the app's current State; Generally my thoughts are; The Camera view needs better access to camera controls using Apple's Native Camera UI. The Main View Needs a iOS Nav Bar at the bottom and header at the top. The Script-Text Overlay Needs a better viewport access to controls. I would like to see your thoughts how to create improvements.

The order I would like to work on the app views:

1. work on Camera Controls Main View w/o nav bar
2. Add Nav Bar + discuss styling
3. work on Compose + Text Overlay Features
4. Add profile.

1a. Initial user Permissions View. One time permissions view.
Permission View should have Vertically Stacked check box permissions for each item access > Camera, Microphone and Photolibrary (video only writing)

1.  Main View should default open to the Selfie Camera.
    The Camera UI should mimic the iOS Native Camera App retaining native iOS camera controls; Touch Auto Focus and Exposure; Camera Record format display panel in Top Left Corner of screen. This is clickable to show camera record settings and adjustments.
    Record Button is Centered like Native iOS.

    Do you want the “native camera controls” to mimic the system Camera app (top controls + bottom shutter strip), or a simplified set (flip, zoom, exposure lock) tailored to teleprompter use?
    For the teleprompter, should scrolling persist position across pause/resume and app backgrounding?
    Should the new bottom nav be a multi-tab shell (e.g., Camera, Scripts, Library, Settings) or a single-screen camera with a custom bottom bar?

2.  Start Script Scroll (Part of Nav Bar)
    style: (Blue Gray/ Blue) (Round Button / Up Triangle) to the left of the record button 1/2 the size of Record. (this is separate so user can test speed)

3.  Compose Script View (Part of Nav Bar)
    toggles script overlay i/o from scroll state to editing state. User can paste/type script (edit) live.

    Keyboard needs swipe down to close and check mark for close

4.  Text Script Overlay needs these features:
    Touch Screen Starting Position Adjustment, default is 66% of screen; ie when the script is initally saved and loaded to the overlay. this can be mid-right screen about thumb width wide. This needs to be a specific location to not interere with Camera Focus and Exposure touch adjustments.

    Adjustment Panel Tab; This tab screen bottom right just above the Nav Bar Is a Toggle Exposing Live Adjustments sliders;
    Scroll Speed
    Font Size + Color White, Black, Red, Blue, Yellow
    Opacity: darkens camera view (not camera exposure) 0 - 15% to improve contrast making the text easier to read.
    Touch Opens and Closes Controls.

    Safe Marker i/o None - 15%

5.  Profile-Setting View (Part of Nav Bar);
    Displays App Version,App Name, Permission settings toggles for Camera, Microphone and Photo library.

6.  Future Backgrounds

- **_ Styling _**

- SWIFT UI and Swift 7 SF Icons
- Theme.swift file to hold styling.

....... May 29 12:36pm
Lets draft a phased development plan make to add unit tests for each part of the code.

- Q1: The first image iPhone17..Mods.png was taken from System Camera for iPhone 17 pro, I added red "XXXX" on camera controls not needed for our selfie camera view. This space for Nav Bar controls. The selfie Camera should keep the Portrait view.
- Q2 yes and the default position of the text position should start above the Record/shutter button and end (go off screen) below the camera recording format display in the top left corner.
- Q3 Yes. Use the image 1 as guide for camera controls to keep/remove, the space we have for the Nav bar and image2.png for placement a Script Play Pause and Nav Controls.
- "Compose" Script View (Part of Nav Bar) toggles script overlay i/o from scroll state to editing state. User can paste/type script (edit) live. Also make sure there is a toggle back.
- The Scrolling controls should be a tab available in bottom right side - I did not add this but it should be a panel toggle for Speed, Text Size, Color and Text BG Opacity to help with views.
- Also rough in a settings button on the nav bar view we develop later.
- Also We will use some icons as we develop the UI so any coding needs to account for this.
- Any questions ask I have more notes but I think this is a good starting point.
