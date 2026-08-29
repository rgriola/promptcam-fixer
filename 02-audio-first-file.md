# Prompt Cam Production Audio Notes:

Internal Mic = Device Native mic iPhone

USB Connected: DJI Mic = DJI Mic 3 Pro - Stereo Wireless mic two independent channels

USB Connected: Rode Mic = Rode Pro Wireless Mic - Stereo Wireless mic two independent channels

Bluetooth Connected: Apple Airpods - Mono one channel

# Expected Audio Work Flow:

If only Internal Mic present, VU Meter shows audio from Internal Mic. Recording Audio is from Internal Mic.

If Internal Mic + USB Connected: USB Mic is auto routed to VU Meter and Recording Audio. Internal Mic is ignored. - Audio Selection Panel State: Should allow creator to select which mic to route. Current Active Mic should be listed at top of the panel.

If Internal Mic + Bluetooth Connected: Bluetooth Mic is auto routed to VU Meter and Recording Audio. Internal Mic is ignored. - Audio Selection Panel State: Should allow creator to select which mic to route. Current Active Mic should be listed at top of the panel.

(Here is the issue)
If Internal Mic + USB Connected + Bluetooth Connected: USB Mic is auto routed to VU Meter and Recording Audio. Internal + Bluetooth Mic are ignored. - Audio Selection Panel State: Should allow creator to select which mic to route. Current Active Mic should be listed at top of the panel.

**_ Issues In Current Production Release Build - Not Current Origin/Main + Changes _**

With two + audio sources Audio Selection Panel does not allow selecting audio source. The first external audio source connected is auto routed - this is to the VU Meter and May be the Recording Audio as well. The Panel State does not work.

The Audio Selection Panel issue is also present with internal + external audio source, however is less noticeable since user intent is most likely to use the presented external mic.

**_ I would like to add Green Messags to Temporay Banner for internal state changes _**
**_ Change Mic Icon to reflect the type of source, if airpods then show airpod icon.
_** Increase sixe of Text on Warning Bannner \*\*\*

**_ non-audio changes _**
For Permission Screen Remove SF Icon and add Cue Vue Icon at the top and create space for the permissoin list.
