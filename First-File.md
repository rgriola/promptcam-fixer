May 29, 2026 - 11:23pm - GitHub Copilot

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

... From GPT

CameraPreviewView.swift

• Clean UIViewRepresentable with AVCaptureVideoPreviewLayer. You might want to add double-tap or long-press gestures later for additional actions (like AE/AF lock) to keep parity with the main view if you want gesture handling centralized.

• Consider exposing videoGravity via an initializer parameter to keep it flexible:

struct CameraPreviewView: UIViewRepresentable {
let session: AVCaptureSession
var videoGravity: AVLayerVideoGravity = .resizeAspect
...
func makeUIView(context: Context) -> PreviewView {
let view = PreviewView()
view.previewLayer.videoGravity = videoGravity
...
}
}

... 8. Teleprompter overlay behavior
• The teleprompter uses TimelineView(.animation(...)) and offsets content. This is fine, but if you notice performance issues on long text, consider precomputing content size and using a repeating animation or withAnimation tied to a timer. Also, resetting startTime on play is good; you might also want to clamp scrolling so it doesn’t run beyond the content height if that’s desired.

... 5. Permissions UX
• You noted these should be moved to a one-time permission view. That would be a nice polish: present a single onboarding screen with checkmarks and links to Settings if denied. After acceptance, proceed to the camera view.
• Also consider handling the case where the user has previously denied permissions by offering a deep link:
if let url = URL(string: UIApplication.openSettingsURLString) {
UIApplication.shared.open(url)
}

.... 3. Gesture interaction improvements
• For the exposure drag, you’re clamping exposureBias and sending deltas to the view model. Consider debouncing or throttling the adjustExposure(by:) calls to avoid overwhelming the camera service during rapid drags. Alternatively, compute a scale factor relative to total vertical travel for smoother mapping.

4. State cleanup and work item lifecycle
   • You correctly cancel the previous hideFocusWorkItem before scheduling a new one. Consider also canceling it in onDisappear to avoid stale work firing if the view is dismissed quickly:
   .onDisappear {
   viewModel.onDisappear()
   hideFocusWorkItem?.cancel()
   hideFocusWorkItem = nil
   }

...

CameraViewModel.swift

• The async permission requests and session start sequence look good. You’re correctly marshalling back to main actor via @MainActor.
• Error and recording state callbacks are captured weakly—good practice.

• Consider surfacing camera formats, FPS options, and resolution in the view model to make formatPanel interactive in the future:
• Properties like availableResolutions, availableFPS, selectedResolution, selectedFPS.
• Methods to apply the selected format to the CameraService.

...
Potential next steps

• Extract a reusable “FocusIndicator” view (currently in CameraView) into its own SwiftUI view with inputs: isVisible, evText, bias, range, and callbacks for drag and long-press. This will make CameraView smaller and the indicator easier to test.
• Add a small settings sheet for toggling grid, resolution, FPS, and maybe a “stabilization” mode if supported by your CameraService.
• Add #Preview SwiftUI previews for CameraView with stubbed view model so you can iterate on UI rapidly without a device.

....

The Short Term Goal is to Wire the Camera Buttons and functions, AE/AF lock is where I left off last night. And through suggestions changes to the subviews as CameraView is doing too much.

The headers and footers styling was an issue so I experimented with the layouts. Not quite there yet.

Answers:

Yes the AE/AF lock should follow native camera behavior; long-pressing directly on the preview target area, instead of requiring long-press on the focus indicator overlay. Yes > For front camera devices without true focus lock, create fallback UX (AE lock only + explicit status text) to avoid false lock feedback.

Yes > produce a no-code Phase 1 exit checklist specifically for AE/AF lock reliability and test criteria before moving further.

Yes > create a subview decomposition map for CameraView (what to split now vs later) that stays strictly within your phased order.

Note I am using print("Specfic Message") to easy test buttons in Xcode, please continue this pattern for buttons and panels.

Next recommended: run a manual on-device gesture feel pass for long-press lock timing and exposure drag smoothness to close the remaining Phase 1 item.
If you want, I can now do a tight header/footer spacing polish pass while still keeping Phase 2 nav content deferred.

... iOS layouts.
anchored natural layout with no offsets:

One overlay container.
Header top-aligned with top padding constant.
Recording cluster bottom-aligned with bottom padding constant.
Footer row bottom-aligned with its own bottom padding constant.
No spacer-driven coupling between those three.

Avoid:

Hardcoding padding, use safe-area-aware layout.
Putting critical actions in transient overlays only.
Letting keyboard cover form controls with no scroll or inset behavior.

... May 31
**_ Task _**
Please review this project.
We are addressing the script starting/endpoint and scrolling issue we worked on last night.

**_ context _**
I want to take a different approach from the Manual Scroll Bar Setting which tried - and fails - to set a script starting point. Turn off the manual scroll bar for now and hide it's UI.

**_ New approach _** Feature allows the user to directly touch screen swipe up/down to shift the script.

The Script traveling start/end points are the first line of script just below Telepriompter Viewport (screen bottom) and Last Line of Script Just Above the Telepriompter Viewport (screen top)

I need one button placed mid-screen right where the manual scroll priviously was positioned; The button resets the script to Telepriompter Viewport Center-midpoint.

Read this back to me, create a plan to impliment this update and place it into a markdown file called teleprompter-fix.md

..
I need a deep evaluation of these three files. I am having placement issues with the script overlay not accomodating any size script. I need options to get this so any size script will start center screeen and completely roll off screen. My first thought it to remove start and endpoint math and always use the Script first line and center screen as the coupled starting points with no enpoint - elminnating the math involved. No coding just a review.

... Jun 1 2026
Evaluate the promptercam-fixer codebase. I am at a point of MVP, the next steps in the development arc is a feature branch then refactoring the codebase before further development in the Phased_Plan.md I am open to simplifying the exsisting codebase including the layouts, elminating duplications, creating and using functions for buttons and other reapeated blocks of code. Also Adding Comments to Make the Code More Readable.

I know CameraView.swift is carrying a lot of responsibilities and needs to be separated out. this is only a code review and refactor plan. Refer to Phased_Plan.md

The first step is creating a feature branch then a code review.

... June 4

Option A. Teleprompter controls Can be a Button to show an adjustment panel for each parameter - so we don't crowd the UI.
The panel should span with the width of the screen up to the bottom of the Teleprompter - does not cover the script only the control portion of the screen.

use SF Symbol: camera.metering.none

The button opens a panel Speed, Font Size, Opacity, Color controls.

Font Size [Slider 16–72, step 2, label shows current pt]
Scroll Speed [Slider 5–150, label shows pts/sec]
Text Color [segmented/swatch row — White/Yellow/Red/Blue/Black]
Background [Slider 0–20%, label shows %]

We should also be able to live adjust the script panel parameters.
And save the last settings for the script controls. We can add a reset button to the panel.

...
**_ Task _**
Add in CameraView CameraTopControlsView() a control slider to onTapEV.

**_ Context _**
The EV Button controls the exposure value for the camera. There is a control function in CameraViewModel > adjustExposure(), this is connected to the EV control in the AF/AE tap but could be used with the EV Button as well.

** Instructions **

- Plan to wire the Camera Header EV button to the EV control, this button should have a slider panel which slides down from the control button.
- When I approve the plan we can code.

** Task **
Turn this into a Button to toggle Camera Auto focus and Auto Exposure and AF/AE Lock - CameraLockStatusBadgeView(status: lockStatus)

**_ Context _**
with the telprompter layer interferes with the the long press auto lock and exposure control and display of the similar yellow box indicator. Moving to a Toggle Auto/ AF/AE Lock status I think is a simple solution.

** Instructions **

- Plan to wire the CameraLockStatusBadgeView(status: lockStatus) as a toggle button.
- Change the current Yellow AF/AE Box lock to temporary display to show the face of interest. It should be a thin yellow line similar to the iOS camera app, show for 3 seconds then fade out. This should activate when the camera opens and toggle of new Auto/ AF/AE Lock Button. Creators can control exposure with the EV bias control.

- When I approve the plan we can code.

** Task **
Add an instruction page section for the guide formerly a grid button > Button(action: onTapGrid)
** ConText **
This section will show guides how to use the app. We can start with one page and I will add more later as swipe through tabs.

first page:
Title: Guide Dog
Text : This is the instructions page to walk through how to use Prompter Cam Fixer.
...

... June 12 2026

**_ Task _**
Lets devise a plan to make these changes with some differences

Full Screen Cover v Sheet -
Keyboard Adjusts background on a Sheet?? why who knows.

... June 25
VU Meter Wrapping

**_ Task _**
Add Transparent Background to VUMeterView.

**_ Issue _**
App does not easily recognize External Mic Input. Also I believe the Auto Focus on the Selfie Camera is interferring or the touch Auto Focus is interferring in Cine Mode. Cine Mode Auto Focus must always be on to work - this is an Apple requirement for that mode.

Ie if the App is in Cine mode at launch the Mic Input does not work. If it is standard, works fine and I can even switch to Cine Mode. Can you trace possible issues. No Coding. Just a plan.

To - Do June 23 from June 16

- Known Issues

[X] Scripting

- Need to reformat copy/paste text to layout correctly from Outlook Pasting
- Converting Script to All Caps, Cap First, All lower
- Remove ==OC== Markers in Script, Ask to reformat script

[Camera Roll] Needs to handle vertical + horizontal video layouts better. Horizontals overplay verticals, probably would be opposite if we were shooting horizontals

[X] Line Navbar (former header) Padding incorrect relation to Camera Preview across devices.

swap STD/CINE Text to toggle, Make Format HD/4K Frame Rate Toggle Pair to remove Sheet function. Note this may change what the user sees - Apple uses a Blur Effect for transition - Keep as is clean up styling

[x] Apeture Panel needs f styling, and default 5.6, Reset button floor setting of 5.6, maybe do stops like a camera.
Custom Slider ?

[x]Change Opacity to Text Contrast.
[x] reduced parameters Prompter Speed :: 32 fine speed,
[X] Camera Roll Button Add a Photo in a Circle to show its the library,
[x] Go to 4 buttons on bottom.

[x] Recall Button icon needs a new design.
[x] I want to move the Cine/Standard Button to the left. I don't like it in the format panel.

#

[x] Reduce size of tap area for Mic Input.

[ ] Add Support for Clicker start/stop. Voice Activated?
[ ] Move Guide Dog to Settings Panel or Make Guide Dog the Settings Panel.

[ ] Teleprompter Text - When scrolling and user touches screen text jumps. Not really and error just looks bad.

[ ] Figure out how to Connect Record and Scroll at the Same time.

[ ] Overlay for tools.

[ ] Add Clean Camera/Audio output to HDMI

- [ ] Add App Guide Pages. Think Handrails for Users
- Insert Images drawn from App with Correct Styles
- Change App Icon + Splash Screen
- Look at cleaner opening for Camera View.
  Script Returns become space + left justified.

Finished issues

- Script View -

[x] Audio input display - grab the name of the Mic set available.
EV Bias Control Panel needs to say "EV Bias"
[X] Easy script clear button to script or remove default text to allow immediate paste or replace current script with new one.
[X] Add a lightweight save for backup should creator lost the script

[x]Recorded Session does not immediatly populate into the Camera Roll. User must close app then reopen to see video. Camera Roll probably needs a UI refresh triggered by the Recording.

[x] App VU meters do not adopt audio source immediately. User must do a soft shutdown and relaunch to refresh the VU meter. This occurs going from iPhone Mic > External Mic and External > iPhone Mic.

- Camera View

  [x]Add VU Meter to left side.

  [X] migrated to Swift 6 & iOS 18+

  [X]High Remove Auto Focus Box. \*\*\* Issue Cannont be removed if tapped outside teleprompter area.

  Test DJI mics [X], Rode []

  {Below both go together}
  High [X] Move Header to footer bellow Rec Button
  High [X]Shift Camera View and Teleprompter up as far as possible.
  High [X]Add Record Timer Display ie 00:01:34

  [x] Change format button + panel to toggle record mode; Pair available quality with frame rate, change button to toggle to move through available HD 30fps, HD 24fps, 4K 30fps, 4k 24fps and Cinematic.

  [x] Cinematic Mode
  - Issues Not being recognized across devices (dynamic adjustments)
  - Front Facing Cameras:
    Standard Mode
    [HD 1920x1080 - 24,30,60]
    [4K - 24,30]
    Cine Mode
    [HD 1920x1080 - 24,30]
    [4K - 24,30]

  - Multiple Front Cameras need to initiallized
  - 4K View is resetting in CameraView

- Script View -

- [x] Added Camera Roll, Video Player with Share and Delete Controls.

- [ ] Add App Guide Pages. Think Handrails for Users
  - Insert Images drawn from App with Correct Styles
  - Change App Icon + Splash Screen
  - Look at cleaner opening for Camera View.

  **_ Task _**
  - Create a plan to replace the full camera roll (RecordingsLibrarySheet) with a direct opening to our player with the last recorded video. This is to allow the creator to immediately review their work.
  - Image Example IMG_0539 shows iOS Native App video Player with a carousel below the timeline. I want to add a similar carousel.
  - The second image IMG_0540 shows our current player implimentation. I would like the onTapPhotoLibrary to open the player directly bypassing the Camera Roll. The Camera Roll can be dormant for now.
  - The only UI additon I would like in our Player is the Carousel below the timeline.
  - trace a better way to populate the carosuel. The camera roll for example always needed to load the video first before moving to the player and it lagged.
  - the carousel only needs first few videos ready not the entire library if this helps with caching and responsiveness.
  - Review and create a plan for approval prior to coding
  - create a new branch prior to coding.

  - Turn off auto play. [x]
  - Some weird overlay that darkens it . [x]

- Carousel active video, one being viewed, needs to connect to main player. Currently the carousel moves but the main player does not,

Create a new 3 - toggle button to set the teleprompter script justification. Use SF Symbols; text.aligncenter (default), text.alignleft Step -1 , text.alignright Step 2, Return to default. Use Theme.white for the color, icon32 for the size.

The user should be able to click through this toggle continuously. The button should be set to the left of the record button similar to how the scroll button is positioned. After reviewing, show me an implimentation plan.

Change Tap Behavior When the Text is scrolling.

User tap in teleprompter area causes text to jump up or down the screen.

**_ Task _**
Modify tap-hold-drag gesture in teleprompter view area to control the text movement.

- Allow user to drag the text up and down with the tap-hold (no jumping text), or pause with no tap-hold, or play with tap-release (depends on Scroll Play/Pause State)

- Tap-hold-drag does not change Scroll Play/Pause Button state - if playing continue, if paused continue.

- Tap-hold-drag feature only valid in teleprompter view area, gesture should not interfere with other active buttons ie; Record, Scroll Play/Pause and Reset Text buttons - all others are gated. Review this gesture and create a plan to implement this change.

**_ Context _** Current state the text jumps up and down the screen regaurdless of the place the tap occurs in the Teleprompter View area.

** Task **
Review how a refactor of CameraView would work with a general reoginization of the ZStack. CameraPreviewView and TeleprompterView still stack on top of each other, other UI items should preform as before. SHow me a plan we can work on. The goal is to correct layout issues, remove duplicate padding,framing and un needed positioning. No Coding.

(New) VStack 1
CameraPreviewView()
cameraControlsRow()
cameraFooter()

(New) VStack 2
TeleprompterView

> > Below each componet should be combined into a single HStack within VStack 2, Each Component here are realted to each other in the stack.

- HStack
  VUmeter
  RecordingClusterView
  TeleprompterUtilityStackView

- Reuseable components
- Componets that are self contained units with no overflow ie; padding is part of the componet.

**_ Issue _**

- User has issue with permissions, when they select "Limited Access" for Photolibrary permission the UI allows them to select Photos where it should only allow videos.

- There are other issues around the photolibrary but focus on tracing this issue.

I switched back to main to work on a more urgent issue causing crashes.
**_ Issue _**
When a user "deletes" a video in the photopicker in app -the app crashes.
**_ Task _**
review the video-player/carousel implementation and see where improvements can be made.
**_ Context _**
The App Delete Flow shows 2 warnings, reguardless of the review remove the 2nd warning with the thumbnail. The delete flow should mark only the current video for deletion, show the user a warning "This video will be deleted", upon deleting the current video should be removed, the video video-player/carousel library should be refreshed.
No Coding just review and plan.

Jul 18, 2026

**_ issue _**
User moves to delete video. No matter which video is the current video the delete button moves to delete the first video (most recently recorded).  
**_ Context _**
Discovered issue on iPhone 17 Pro device. User in Full Photo Access. 2nd Delete message showed first video thumbnail though video-player was cued to a different video.

4:38pm
Question when the user selects limited photo library access in settings there a sheet pops up allowing the user to select either photos or videos. In this case I close this window without a selectios.

Selecting a video in Limited mode the user cannot select more videos after the first selection, the limited feature cuts off the auto populate sheet.

july 27

**_ issue _**
When user opens the app video-player-carousel the app eventually crashes. The entire feature is slow and jerky. Tapping the icon button just to open the is akwardly slow. We need a full review of the features and code causing these issues.

**_ Context _**
The Native iOS app also has a carousel player ui and it is not this slow. Are the thumbnails created differently? Are we calling the assests multiple times to creatw the player and carousel?

July 28
In Settings View > Formats I believe the formats displayed are incorrect. Can you trace to see if this is true. The formats shown here are only ones available for this app; Front Camera; Cine or Standand Mode Camera; 4k or 1080; 24p, 30p or 60p - if available.

I found an issue where in script view with voice dication to write out the script > save > the camera preview is frozen returning to the main UI, the rest of the app seemingly works. Closing and opening the app refreshes the Camera Preview and the script is still present as it should.

July 29
** issue **
We are working on an issue where the Camera Preview fails to restart properly after using speech-to-text feature in script view. We pushed two fixes last night but device testing shows the issue persists.

**_ Context _**
In Script View user selects speech-to-text feature > saves the script > returns to main view camera preview is frozen. It may be speech-to-text does not release the audio session, camera preview does not start back up.

Testing on device, iPhone 17, the green circle camera active indicator on the dynamic island is present at the start of script view. Selecting speech-to-text this circle turns to orange indicating the camera preview is off but the microphone is still active. Returning to the main view the orange circle is still on, camera preview is frozen. This is confirmed in several device tests.

We need another look at the coding issue.
