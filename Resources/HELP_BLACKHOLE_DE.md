# AudioDaBitch Help / BlackHole Routing

## Goal
Route Discord and xPilot into virtual BlackHole devices first. AudioDaBitch then applies channel leveling, ducking, panning and limiting before anything reaches your headphones.

## Signal Flow
Discord  -> BlackHole 2ch  -> AudioDaBitch Discord channel 1 -> Output
xPilot   -> BlackHole 16ch -> AudioDaBitch xPilot channel 2  -> Output
Output   -> Headphones, headset or audio interface

## Important
! Do not use a Multi-Output device with your headphones.
  That creates a direct path around the limiter, so loud audio can bypass AudioDaBitch.

## Recommended macOS Audio MIDI Setup
* BlackHole 2ch: 48,000 Hz
* BlackHole 16ch: 48,000 Hz
* Headphones / headset / audio interface: 48,000 Hz when available

## Discord
* Input Device: your normal microphone
* Output Device: BlackHole 2ch
* AudioDaBitch Discord Input: BlackHole 2ch

## xPilot
* Microphone/Input: your normal microphone
* Headset Device: BlackHole 16ch
* Speaker Device: BlackHole 16ch
* AudioDaBitch xPilot Input: BlackHole 16ch

## Leveling
* Discord channel 1 and xPilot channel 2 can now be leveled independently.
* Target loudness controls the speech level each channel tries to reach.
* Maximum boost limits how much quiet voices may be raised.
* Maximum cut limits how strongly loud voices may be reduced.
* Response speed controls how quickly the correction reacts.

## Ducking
* xPilot priority ducking lowers Discord when ATC or another pilot is present.
* Trigger threshold decides how quiet xPilot audio can be before ducking starts.
* Discord reduction controls how much Discord is lowered.
* Attack should stay low for immediate ATC priority.
* Release controls how smoothly Discord returns after xPilot is quiet.

## If Audio Crackles
1. Click Stabilize Audio.
2. Set all involved devices to 48,000 Hz in Audio MIDI Setup.
3. Avoid Bluetooth headphones when low latency matters.
4. Open Logs and create a Log ZIP if you need to send diagnostics.
