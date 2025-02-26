# GrooveAnimator - Custom Animation Handler for Roblox

`GrooveAnimator` is a lightweight, virtual animation handler designed for Roblox, enabling smooth keyframe sequence animation playback without an instance overhead. It excels at compositing multiple animations or replacing Roblox’s default animator.

## Features
- **Virtual Animations**: No instance overhead.
- **Blend Masking**: Composite multiple animations together.
- **Keyframe Flexibility**: Supports custom sequences and binary storage for fast loading.
- **Custom Easing**: Extendable easing styles for tailored animation curves.
- **Roblox-Friendly**: Integrates naturally with Roblox rigs and workflows.

## Installation
1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/GrooveAnimator.git
   ```
2. Copy `GrooveAnimator.lua` into your Roblox project.
3. Require it in your script:
   ```lua
   local GrooveAnimator = require(game.ReplicatedStorage.GrooveAnimator)
   ```

## API

`GrooveAnimator.newController()`
Creates an animation controller similar to Roblox’s `AnimationController`.
- **Returns**: `GrooveController`

`GrooveAnimator.newTrack(sequence: GrooveKeyframeSequence)`
Creates a track backed by a `GrooveKeyframeSequence`.
- **Parameters**: `sequence` - A `GrooveKeyframeSequence` object.
- **Returns**: `GrooveTrack`

`GrooveAnimator:ImportKeyframeSequence(sequence: KeyframeSequence)`
Converts a Roblox `KeyframeSequence` into a `GrooveKeyframeSequence`.
- **Parameters**: `sequence` - A Roblox `KeyframeSequence`.
- **Returns**: `GrooveKeyframeSequence`

`GrooveAnimator:ImportSerialized(buf: buffer)`
Deserializes a `GrooveKeyframeSequence` from a binary buffer.
- **Parameters**: `buf` - A buffer containing serialized data.
- **Returns**: `GrooveKeyframeSequence`

`GrooveAnimator:RegisterEasingStyle(style: string, easing_map: {[Enum.EasingDirection]: (alpha: number)->(number)})`
Registers a custom easing style with a callback function.
- **Parameters**:
  - `style` - Name of the easing style (e.g., "CustomEase").
  - `easing_map` - k,v map where each key is a `Enum.EasingDirection` and each value is a callback function

## Example Usage
Here’s how to animate a rig with `GrooveAnimator`:

```lua
local GrooveAnimator = require(game.ReplicatedStorage.GrooveAnimator)

-- Source rig
local rig = script.Parent.Rig

-- Create and play a track from an existing KeyframeSequence
local grooveTrack = GrooveAnimator.newTrack(GrooveAnimator:ImportKeyframeSequence(rig.AnimSaves["Bounce"]))
grooveTrack:Play()

-- Set up a controller
local grooveController = GrooveAnimator.newController()
grooveController:AddTrack(grooveTrack)

-- Attach the rig for automatic updates
local grooveRig = grooveController:AttachRig(rig)

-- Step animations each frame
game:GetService("RunService").Heartbeat:Connect(function(deltaTime)
    grooveController:Step(deltaTime)
end)
```

## How It Works
1. **Import or Create Sequences**: Use `ImportKeyframeSequence` or load from binary with `ImportSerialized`.
2. **Track Management**: Create tracks with `newTrack` and control playback.
3. **Controller Setup**: Use `newController` to manage multiple tracks and attach rigs.
4. **Step Updates**: Call `Step` in a loop (e.g., via `Heartbeat`) to apply animations.

## Why GrooveAnimator?
- Perfect for projects needing complex animation blending without performance hits.
- Stores sequences in binary for compact, fast-loading animations, on demand. No CDN!
- Replaces Roblox’s default animator with a virtual alternative.

## Contributing
Contributions are welcome! Fork this repo, add features, or submit pull requests. Issues or suggestions? Open a ticket!

## Author
- **Andrew Hamilton (orange451)**

## License
Licensed under the MIT License. See [LICENSE](LICENSE) for details.
