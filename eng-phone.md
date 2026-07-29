New Project
iPhone ENG
The purpose of this app is to provide a simple to use camera for news.

Video Recording, Camera Preview, Audio Session, Live Video-Audio Output to HDMI (1080p)

- Front Camera (Selfie Camera)
- Back Camera(s)

- Camera Controls to set record formats
  Standard, Cine
  4k, UHD, HD
  24p, 30p, 60p
  (slow-mo options not supported)

- Back Camera Controls:
  Zoom Control
  White Balence (Auto / Manual) Manual Presets 3200k, 4500k, 6200k
  Tap Focus Control/Focus Lock/Focus Track
  ISO Controls in steps Auto, 100, 200, 400, 800, 1600, 3200+ (no half steps)
  Tap Exposure Control (I am not sure iOS camera exposure may be controlled by ISO not apature)
  Focus and Exposure seems to be handled by other apps in a circle combining both controls.

- Front (Selfie) Camera Controls:
  Simple Auto everything

- Audio Multi Channel Input/Output
  Audio detection iPhone Mic > External Mic > iPhone hotswapping, also no audio alert
  Audio Channel Routing Selection > iPhone or External or OFF.
  Audio Volume Control -

- Live Video Output USB > HDMI output - Button to provide clean video output
  Allow Vertical or Horizontal output with open gate - no screen view just video
  Camera Preview/Output is always related to USB Port position:
  Port on Bottom vertical recording + Live Vertical HDMI output + Recording Telemetry
  Port on Right horizontal recording + Live Horizonal HDMI output + Recording Telemetry

  NOTE: Video Library must allow video playout live via USB - HDMI (1080p)

- Full Metadata Capture to recording.

User Interface:
Use Swift UI, SF symbols; only use UIKit when no option exsists for specific need
App UI must allow rotation Vertical + Horizontal

Buttons must be reusable; Button template is created and reused.

Views:
Camera View - This is where creators land first.
Photolibrary - Video Only with player/carousel.
Settings - Standard UI for Creator settings for permissions, support, app version and some macro app settings TBD

Extras:
Initial app development will not have Auth but include sockets to add Auth later in development.

Photo Libray is Video Only:

- Share Extention to connect to other apps internally
