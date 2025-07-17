--!strict
--!native

--[[
	-------------------------------------------------------------------------------------------------------
	  ____                                            ______                                    __           
	/'  __`\                                         /\  _  \          __                      /\ \__                
	\ \ \L_/_  _ __   ___     ___   __  __     __    \ \ \L\ \    ___ /\_\    ___ ___      __  \ \ ,_\   ___   _ __  
	 \ \ \`_ \/\`'__\/ __`\  / __`\/\ \/\ \  /'__`\   \ \  __ \ /' _ `\/\ \ /' __` __`\  /'__`\ \ \ \/  / __`\/\`'__\
	  \ \ \L\ \ \ \//\ \L\ \/\ \L\ \ \ \_/ |/\  __/    \ \ \/\ \/\ \/\ \ \ \/\ \/\ \/\ \/\ \L\.\_\ \ \_/\ \L\ \ \ \/ 
	   \ \____/\ \_\\ \____/\ \____/\ \___/ \ \____\    \ \_\ \_\ \_\ \_\ \_\ \_\ \_\ \_\ \__/.\_\\ \__\ \____/\ \_\ 
	    \/___/  \/_/ \/___/  \/___/  \/__/   \/____/     \/_/\/_/\/_/\/_/\/_/\/_/\/_/\/_/\/__/\/_/ \/__/\/___/  \/_/
	-------------------------------------------------------------------------------------------------------
	Easily animate keyframe sequences in a Roblox-friendly style. All virtual, so there is no instance waste.
		This can be used for many applications, but was born out of the necessity for blend masking. Using
		this module you can easily composite multiple animations together, or use it as a replacement for
		the default roblox animator.
		
		KeyframeSequences can be written to a binary format for convenient storage and fast loading.
	-------------------------------------------------------------------------------------------------------
	Version: 1.0.5
	Author: Andrew Hamilton (orange451)
	-------------------------------------------------------------------------------------------------------
	Changelog:
		1.0.0 - February 25th, 2025 - Initial Release
		1.0.1 - March 2nd, 2025 - Fixed Play() and Stop() functions from breaking tracks
		1.0.2 - March 6th, 2025 - Added EncodeBuffer/DecodeBuffer functions
		1.0.3 - March 19th, 2025 - Added GrooveRig.ComputeWorldPoseTransform and GrooveController.ComputeAncestorPoses
		1.0.4 - March 19th, 2025 - Added ComputePoseTransform. Added GrooveRig.Animatable
		1.0.5 - July 17th, 2025 - Fixed bug where Pose Weights were not factored in to final weight
	-------------------------------------------------------------------------------------------------------
	API:
		GrooveAnimator.newController() - function
			Creates a controller object for your animations. Similar to an AnimationController
		GrooveAnimator.newTrack(sequence: GrooveKeyframeSequence) : GrooveTrack
			Creates a new GrooveTrack object backed by a GrooveKeyframeSequence.
		GrooveAnimator:ImportKeyframeSequence(sequence: KeyframeSequence) : GrooveKeyframeSequence
			Converts a roblox KeyframeSequence object in to a GrooveKeyframeSequence.
		GrooveAnimator:ImportSerialized(buf: buffer) : GrooveKeyframeSequence
			Deserializes a GrooveKeyframeSequence stored as a buffer.
		GrooveAnimator:RegisterEasingStyle(style: string, easing_map: {[Enum.EasingDirection]: (alpha: number)->(number)})
			Registers a new easing style with the given easing map.
		GrooveAnimator:EncodeBuffer(input_buffer: buffer) : string
			Converts a buffer in to a hex readible string
		GrooveAnimator:DecodeBuffer(input_string: string) : buffer
			Converts a hex redible string in to a buffer
	-------------------------------------------------------------------------------------------------------
	Example Usage:
		-- Source rig
		local rig = script.Parent.Rig

		local groove_track = GrooveAnimator.newTrack(GrooveAnimator:ImportKeyframeSequence(rig.AnimSaves["Bounce"]))
		groove_track:Play()

		-- Create controller
		local groove_controller = GrooveAnimator.newController()
		groove_controller:AddTrack(groove_track)

		-- Assign animatible rig (This makes the rig automatically update on step)
		local groove_rig = groove_controller:AttachRig(rig)

		-- Step and apply animation
		game:GetService("RunService").Heartbeat:Connect(function(delta_time)
			groove_controller:Step(delta_time)
		end)
]]

local module = {}

local Signal = require(script.Signal) -- Should support any signal library that resembles RBXScriptSignal

local TweenService = game:GetService("TweenService")

local lerp = math.lerp

type PosesInterface = {
	Name: string,
	Poses: {GroovePose},
	Parent: PosesInterface?
}

export type GrooveEasingFunction = (alpha: number, easing_direction: Enum.EasingDirection)->(number)

export type GroovePose = {
	CFrame: CFrame,
	EasingDirection: Enum.EasingDirection,
	EasingStyle: string,
	Weight: number,
} & PosesInterface

export type GrooveKeyframe = {
	Time: number,
	PoseMap: {[string]: GroovePose},
} & PosesInterface

export type GrooveKeyframeSequence = {
	Keyframes: {GrooveKeyframe},
	Loop: boolean,
	Name: string,

	Serialize: (self: GrooveKeyframeSequence) -> (buffer),
}

export type GrooveTrack = {
	Sequence: GrooveKeyframeSequence,

	Looped: boolean,
	IsPlaying: boolean,

	WeightCurrent: number,
	WeightTarget: number,

	Length: number,
	TimePosition: number,
	Speed: number,

	KeyframeIndex: number,

	Name: string,

	KeyframeReached: Signal.Signal<(keyframeName: string, keyframeIndex: number) -> (), string, number>,
	Stepped: Signal.Signal<(dt: number) -> (), number>,

	Play: (self: GrooveTrack, transition_time: number?, speed: number?, weight: number?)->(),
	Stop: (self: GrooveTrack, transition_time: number?)->(),

	AdjustSpeed: (self: GrooveTrack, speed: number, transition_time: number?)->(),
	AdjustWeight: (self: GrooveTrack, weight: number, transition_time: number?)->(),

	Destroy: (self: GrooveTrack)->(),
}

export type GrooveController = {
	Tracks: {GrooveTrack},
	Step: (self: GrooveController, delta_time: number, output_transforms: {[string]: CFrame}?)->({[string]: CFrame}),
	AttachRig: (self: GrooveController, rig: Model) -> (GrooveRig),
	AddTrack: (self: GrooveController, track: GrooveTrack)->(),
	RemoveTrack: (self: GrooveController, track: GrooveTrack)->(),
	Destroy: (self: GrooveController)->(),

	CachedPoses: {[string]: GroovePose},

	Stepped: Signal.Signal<(dt: number, transforms: {[string]: CFrame}) -> (), number, {[string]: CFrame}>,

	GetPlayingAnimationTracks: (self: GrooveController)->({GrooveTrack}),

	ComputeAncestorPoses: (self: GrooveController, bone_name: string)->({GroovePose}),
}

export type GrooveRig = {
	Model: Model,
	ComputePoseTransform: (self: GrooveRig, bone_name: string)->(CFrame),
	ComputeWorldPoseTransform: (self: GrooveRig, bone_name: string)->(CFrame),
	Animatable: boolean,
	TrackScale: boolean,
	Destroy: (self: GrooveRig)->(),
}

local poseEasingStyleMap: {[Enum.PoseEasingStyle]: Enum.EasingStyle?} = {
	[Enum.PoseEasingStyle.Linear] = Enum.EasingStyle.Linear,
	[Enum.PoseEasingStyle.Elastic] = Enum.EasingStyle.Elastic,
	[Enum.PoseEasingStyle.Cubic] = Enum.EasingStyle.Cubic,
	[Enum.PoseEasingStyle.Bounce] = Enum.EasingStyle.Bounce,
	[Enum.PoseEasingStyle.CubicV2] = Enum.EasingStyle.Cubic,
	[Enum.PoseEasingStyle.Constant] = nil
}

-- Build out easing style map
local easingStyleMap: {[string]: (alpha: number, easing_direction: Enum.EasingDirection)->(number)} = {}
for _,v in pairs(Enum.EasingStyle:GetEnumItems()) do
	easingStyleMap[v.Name] = function(alpha: number, easing_direction: Enum.EasingDirection)
		return TweenService:GetValue(alpha, v, easing_direction)
	end
end

-- Override Linear callback so we dont have to call a service!
easingStyleMap[Enum.EasingStyle.Linear.Name] = function(alpha: number, easing_direction: Enum.EasingDirection)
	return alpha
end

local function findBoundingKeyframes(keyframe_sequence: GrooveKeyframeSequence, targetTime: number) : (GrooveKeyframe, GrooveKeyframe, number, number)
	local sortedKeyframes = keyframe_sequence.Keyframes

	local low = 1
	local high = #sortedKeyframes
	local leftKeyframe = nil
	local rightKeyframe = nil

	while low <= high do
		local mid = (low + high) // 2
		local midTime = sortedKeyframes[mid].Time

		if midTime < targetTime then
			leftKeyframe = sortedKeyframes[mid]
			low = mid + 1
		else
			rightKeyframe = sortedKeyframes[mid]
			high = mid - 1
		end
	end

	return leftKeyframe, rightKeyframe, low-1, high+1
end

local function getPlayingTracks(self: GrooveController) : ({GrooveTrack}, number)
	local tracks = {}

	local total_weight = 0

	for _,track in ipairs(self.Tracks) do
		if ( track.IsPlaying ) then
			table.insert(tracks, track)

			total_weight += track.WeightCurrent
		end
	end

	return tracks, math.max(1, total_weight)
end

local function step(self: GrooveController, delta_time: number, output_transforms: {[string]: CFrame})
	local playing_tracks, total_weight = getPlayingTracks(self)

	for i=1, #playing_tracks do
		local track = playing_tracks[i]

		-- Compute how much of the total weight this track takes up
		local track_weight_alpha = track.WeightCurrent / total_weight

		-- Step the track
		track.TimePosition = track.TimePosition + delta_time * track.Speed

		-- Loop or clamp the current time.
		local is_last_frame = false
		if track.TimePosition > track.Length then
			if track.Looped then
				track.TimePosition -= track.Length

				-- Play changed keyframe for last keyframe (We skip it visually)
				local _, last_keyframe, _, last_index = findBoundingKeyframes(track.Sequence, track.Length)
				track.KeyframeReached:Fire(last_keyframe.Name, last_index)
			else
				track.TimePosition = track.Length
				is_last_frame = true
			end
		end

		-- Find the keyframes to the left and right of the current time. TODO see if we can do some clever tricks to cache these as much as possible
		local left, right, left_index, right_index = findBoundingKeyframes(track.Sequence, track.TimePosition)
		if not left and right then
			left = right
		elseif left and not right then
			right = left
		end

		-- Figure out keyframe changed.
		local use_index = is_last_frame and right_index or left_index
		local use_keyframe = is_last_frame and right or left
		if ( use_index ~= track.KeyframeIndex ) then
			track.KeyframeIndex = use_index
			track.KeyframeReached:Fire(use_keyframe.Name, use_index)
		end

		-- Calculate the interpolation factor.
		local t = 0
		if left.Time ~= right.Time then
			t = (track.TimePosition - left.Time) / (right.Time - left.Time)
		end

		-- Lerp pose transforms.
		for name, leftPose in pairs(left.PoseMap) do
			local rightPose = right.PoseMap[name] or leftPose

			-- Compute the tween value.
			local easingStyle, lerp_ratio = leftPose.EasingStyle, 0
			local easingFunction = easingStyleMap[easingStyle]
			if ( easingFunction ) then
				lerp_ratio = easingFunction(t, leftPose.EasingDirection)
			end

			-- Compute transform.
			local rightCFrame = rightPose.CFrame
			local newCFrame = leftPose.CFrame:Lerp(rightPose.CFrame, lerp_ratio)

			-- Store.
			local old_value = output_transforms[name]
			local pose_weight = track_weight_alpha * lerp(leftPose.Weight, rightPose.Weight, t)
			output_transforms[name] = (old_value or CFrame.identity):Lerp(newCFrame, pose_weight)

			if ( not old_value ) then
				self.CachedPoses[name] = leftPose
			end
		end

		if ( track.Stepped._handlerListHead ) then
			track.Stepped:Fire(delta_time)
		end
	end

	if ( self.Stepped._handlerListHead ) then
		self.Stepped:Fire(delta_time, output_transforms)
	end

	return output_transforms
end

local function computeAncestorPoses(self: GrooveController, pose_name: string) : {GroovePose}
	local poses: {GroovePose} = {}

	local node: PosesInterface = self.CachedPoses[pose_name]
	while(node) do
		local parent_node = node.Parent
		if ( not parent_node or parent_node.Name == "Keyframe" ) then
			break
		end

		table.insert(poses, parent_node :: GroovePose)
		node = parent_node
	end

	return poses
end

-- This is just a utility class
-- It is suggested that you make your own solution to apply the transforms to your rig
local function newRig(self: GrooveController, rig: Model) : GrooveRig
	local controller = self

	local scale = rig:GetScale() or 1

	local lastTransforms: {[string]: CFrame} = {}

	-- Cache the motors for quick animation transforms
	local part_name_to_motor_map: {[string]: (Motor6D|Bone)} = {}
	do
		local function check_motors(root: Instance?)
			if ( not root ) then
				return
			end

			for _,v in ipairs(root:GetChildren()) do
				if ( v:IsA("Motor6D") ) then
					local part1 = v.Part1
					if ( part1 and not part_name_to_motor_map[part1.Name] ) then
						part_name_to_motor_map[part1.Name] = v
						check_motors(part1)
					end
				elseif ( v:IsA("Bone") ) then
					if ( not part_name_to_motor_map[v.Name] ) then
						part_name_to_motor_map[v.Name] = v
						check_motors(v)
					end
				end
			end
		end

		for _,v in pairs(rig:GetChildren()) do
			check_motors(v)
		end
	end

	local connections: {Signal.Connection} = {}

	local function transform_scale(transform: CFrame, scale: number)
		return CFrame.fromMatrix(transform.Position * scale, transform.XVector, transform.YVector, transform.ZVector)
	end

	local function computePoseTransform(self: GrooveRig, pose_name: string)
		local scale = rig:GetScale()
		local poses = controller:ComputeAncestorPoses(pose_name)

		local function getTransform(bone_name: string)
			local parent_transform = transform_scale(lastTransforms[bone_name] or CFrame.identity, scale)

			local motor = part_name_to_motor_map[bone_name] :: Motor6D
			if ( not motor ) then
				return CFrame.identity
			end

			local motor_transform = motor.C0
			return motor_transform * parent_transform
		end

		local transform = CFrame.identity
		for _,v in poses do
			transform = getTransform(v.Name) * transform
		end

		transform = transform * getTransform(pose_name)

		return transform
	end

	local function computeWorldPoseTransform(self: GrooveRig, pose_name: string)
		return rig:GetPivot() * computePoseTransform(self, pose_name)
	end

	local groove_rig: GrooveRig = {
		Model = rig,

		Animatable = true,

		TrackScale = false,

		Destroy = function(self: GrooveRig)
			for _,v in ipairs(connections) do
				v:Disconnect()
			end

			table.clear(connections)

			for k,_ in pairs(self) do
				self[k] = nil
			end

			(self :: any)._destroyed = true
		end,

		ComputePoseTransform = computePoseTransform,

		ComputeWorldPoseTransform = computeWorldPoseTransform,
	}

	table.insert(connections, controller.Stepped:Connect(function(dt: number, transforms: {[string]: CFrame})
		lastTransforms = transforms

		if ( groove_rig.Animatable ) then
			if ( self.TrackScale ) then
				scale = rig:GetScale()				
			end

			for partName, transform in pairs(transforms) do
				local motor = part_name_to_motor_map[partName] :: Motor6D -- (Force it to be a motor so the intellisense stops being annoying)
				if ( not motor ) then
					continue
				end

				if ( scale == 1 ) then
					motor.Transform = transform
				else
					motor.Transform = transform_scale(transform, scale)

					-- Same logic as above:
					--motor.Transform = CFrame.new(transform.Position * scale) * transform.Rotation
				end
			end
		end
	end))

	return groove_rig	
end

-- Constructor for GrooveController
function module.newController() : GrooveController
	local controller: GrooveController = {
		Tracks = {},
		CachedPoses = {},
		Stepped = Signal.new(),

		GetPlayingAnimationTracks = function(self: GrooveController)
			local tracks,_ = getPlayingTracks(self)
			return tracks
		end,

		Step = function(self: GrooveController, delta_time: number, output_transforms: {[string]: CFrame}?)
			return step(self, delta_time, output_transforms or {})
		end,

		AddTrack = function(self: GrooveController, track: GrooveTrack)
			table.insert(self.Tracks, track)
		end,

		RemoveTrack = function(self: GrooveController, track: GrooveTrack)
			local index = table.find(self.Tracks, track)
			if ( index ) then
				table.remove(self.Tracks, index)
			end
		end,

		Destroy = function(self: GrooveController)
			-- Destroy tracks
			for _,track in pairs(self.Tracks) do
				track:Destroy()
			end

			-- Nil out everything
			for k,_ in pairs(self) do
				self[k] = nil
			end
		end,

		ComputeAncestorPoses = computeAncestorPoses,

		AttachRig = newRig,
	}

	return controller
end

-- Constructor for GrooveTrack
-- keyframe_sequence: A GrooveKeyframeSequence containing keyframe data
function module.newTrack(keyframe_sequence: GrooveKeyframeSequence) : GrooveTrack
	assert(keyframe_sequence ~= nil)

	local animation_length = #keyframe_sequence.Keyframes > 0 and keyframe_sequence.Keyframes[#keyframe_sequence.Keyframes].Time or 0

	local speed_index = 0
	local function adjust_speed(self: GrooveTrack, target_speed: number, duration: number, callback: ()->()?)

		local new_index = speed_index + 1
		speed_index = new_index

		local function isInterrupted()
			return speed_index ~= new_index
		end

		local function update(initial_speed, target_speed, x)
			if ( isInterrupted() ) then
				return
			end

			if ( x >= 1 ) then
				self.Speed = target_speed
			else
				self.Speed = lerp(initial_speed, target_speed, x)
			end
		end

		local function finish()
			if ( callback and self.Speed == target_speed and not isInterrupted() ) then
				callback()
			end
		end

		if ( duration <= 0 ) then
			update(0, target_speed, 1)

			finish()
		else
			task.spawn(function()
				local i_transition_time = 1/duration
				local initial_speed = self.Speed
				local x = 0

				while(x < 1 and not isInterrupted()) do
					local delta = task.wait() * i_transition_time
					x = math.clamp(x + delta, 0, 1)
					update(initial_speed, target_speed, x)
				end

				finish()
			end)
		end
	end

	local weight_index = 0
	local function adjust_weight(self: GrooveTrack, weight: number, duration: number, callback: ()->()?)

		local new_index = weight_index + 1
		weight_index = new_index

		local function isInterrupted()
			return weight_index ~= new_index
		end

		local function update(initial_weight, target_weight, x)
			if ( isInterrupted() ) then
				return
			end

			if ( x >= 1 ) then
				self.WeightTarget = target_weight
			else
				self.WeightCurrent = lerp(initial_weight, target_weight, x)
			end
		end

		local function finish()
			if ( callback and self.WeightTarget == weight and not isInterrupted() ) then
				callback()
			end
		end

		if ( duration <= 0 ) then
			update(0, weight, 1)

			finish()
		else
			task.spawn(function()
				local i_transition_time = 1/duration
				local initial_weight = self.WeightCurrent
				local x = 0

				while(x < 1 and not isInterrupted()) do
					local delta = task.wait() * i_transition_time
					x = math.clamp(x + delta, 0, 1)
					update(initial_weight, weight, x)
				end

				finish()
			end)
		end
	end

	local animation_clip: GrooveTrack = {
		Sequence = keyframe_sequence,
		Length = animation_length,
		Looped = keyframe_sequence.Loop,
		TimePosition = 0,

		WeightTarget = 1,
		WeightCurrent = 1,

		KeyframeIndex = 0,

		IsPlaying = false,
		Speed = 1,

		Name = keyframe_sequence.Name,

		KeyframeReached = Signal.new(),
		Stepped = Signal.new(),

		Destroy = function(self: GrooveTrack)
			for k,_ in pairs(self) do
				self[k] = nil
			end
		end,

		Play = function(self: GrooveTrack, transition_time: number?, speed: number?, weight: number?)
			local target_speed = speed or 1
			local target_weight = weight or 1
			transition_time = transition_time or 0.2

			assert(typeof(target_speed) == "number")
			assert(typeof(target_weight) == "number")
			assert(typeof(transition_time) == "number")

			self.IsPlaying = true

			adjust_speed(self, target_speed, transition_time)
			adjust_weight(self, target_weight, transition_time)
		end,

		Stop = function(self: GrooveTrack, transition_time: number?)
			transition_time = transition_time or 0.2
			assert(typeof(transition_time) == "number")

			adjust_weight(self, 0, transition_time, function()
				self.IsPlaying = false
			end)
		end,

		AdjustWeight = function(self:GrooveTrack, weight: number, transition_time: number?)
			transition_time = transition_time or 0.2
			assert(typeof(transition_time) == "number")

			adjust_weight(self, weight, transition_time)
		end,

		AdjustSpeed = function(self:GrooveTrack, speed: number, transition_time: number?)
			local target_speed = speed or 1
			transition_time = transition_time or 0.2

			assert(typeof(target_speed) == "number")
			assert(typeof(transition_time) == "number")

			adjust_speed(self, target_speed, transition_time)
		end,
	}

	-- TODO replace weight/speed adjustment to work based on this dt.
	--animation_clip.Stepped:Connect(function(dt: number)
	--	--
	--end)

	return animation_clip
end

local function serializeKeyframe(self: GrooveKeyframeSequence)
	-- Table to collect binary parts
	local parts = {}

	-- Write Loop as uint8 (1 byte)
	table.insert(parts, string.pack("B", self.Loop and 1 or 0))

	-- Write Name: length (uint32) + string data
	table.insert(parts, string.pack("I4", #self.Name) .. self.Name)

	-- Write number of Keyframes as uint32 (4 bytes)
	table.insert(parts, string.pack("I4", #self.Keyframes))

	-- Process each Keyframe
	for _, keyframe in ipairs(self.Keyframes) do
		-- Write Time as double (8 bytes)
		table.insert(parts, string.pack("d", keyframe.Time))

		-- Write Name: length (uint32) + string data
		table.insert(parts, string.pack("I4", #keyframe.Name) .. keyframe.Name)

		-- Collect PoseMap entries to determine count
		local entries = {}

		-- Process each PoseMap entry
		for key, value in pairs(keyframe.PoseMap) do
			-- Build the entry string
			local entry = ""
			-- Key: length (uint32) + string data
			entry = entry .. string.pack("I4", #key) .. key
			-- Name: length (uint32) + string data
			entry = entry .. string.pack("I4", #value.Name) .. value.Name
			-- Parent Name: length (uint32) + string data
			local parentPoseName = value.Parent and value.Parent.Name or ""
			entry = entry .. string.pack("I4", #parentPoseName) .. parentPoseName
			-- CFrame: 12 doubles from GetComponents()
			entry = entry .. string.pack("dddddddddddd", value.CFrame:GetComponents())
			-- EasingDirection: enum value as uint32
			entry = entry .. string.pack("I4", value.EasingDirection.Value)
			-- EasingStyle: length (uint32) + easing style name
			entry = entry .. string.pack("I4", #value.EasingStyle) .. value.EasingStyle
			-- Weight: double
			entry = entry .. string.pack("d", value.Weight)

			table.insert(entries, entry)
		end

		-- Write number of PoseMap entries as uint32 (4 bytes)
		table.insert(parts, string.pack("I4", #entries))

		-- Append all PoseMap entries
		for _, entry in ipairs(entries) do
			table.insert(parts, entry)
		end
	end

	-- Concatenate all parts into a single binary string
	local binary = table.concat(parts)

	-- Create and return the buffer
	return buffer.fromstring(binary)
end

local function newPose()
	local pose: GroovePose = {
		Name = "Pose",
		CFrame = CFrame.identity,
		EasingDirection = Enum.EasingDirection.Out,
		EasingStyle = Enum.EasingStyle.Linear.Name,
		Parent = nil,
		Weight = 1,
		Poses = {}
	}

	return pose
end

local function newKeyframe()
	local keyframe: GrooveKeyframe = {
		Name = "Keyframe",
		Time = 0,
		Poses = {},
		PoseMap = {},
	}

	return keyframe
end

local function newKeyframeSequence()
	local sequence: GrooveKeyframeSequence = {
		Keyframes = {},
		Loop = false,
		Name = "KeyframeSequence",

		Serialize = serializeKeyframe,
	}

	return sequence
end

function module:ImportSerialized(buf: buffer) : GrooveKeyframeSequence
	local offset = 0
	local data = newKeyframeSequence()

	-- Read Loop flag (uint8)
	local loopByte = buffer.readu8(buf, offset)
	data.Loop = loopByte == 1
	offset = offset + 1

	-- Read Name string (length-prefixed)
	local nameLen = buffer.readu32(buf, offset)
	offset = offset + 4
	data.Name = buffer.readstring(buf, offset, nameLen)
	offset = offset + nameLen

	-- Read number of Keyframes (uint32)
	local numKeyframes = buffer.readu32(buf, offset)
	offset = offset + 4

	-- Process each Keyframe
	for i = 1, numKeyframes do
		local keyframe = newKeyframe()

		-- Read Time (double)
		keyframe.Time = buffer.readf64(buf, offset)
		offset = offset + 8

		-- Read Name string (length-prefixed)
		local nameLen = buffer.readu32(buf, offset)
		offset = offset + 4
		keyframe.Name = buffer.readstring(buf, offset, nameLen)
		offset = offset + nameLen

		-- Read number of PoseMap entries (uint32)
		local numEntries = buffer.readu32(buf, offset)
		offset = offset + 4

		local parentMap: {[string]: string} = {}

		-- Process each PoseMap entry
		for j = 1, numEntries do
			-- Read Key string (length-prefixed)
			local keyLen = buffer.readu32(buf, offset)
			offset = offset + 4
			local key = buffer.readstring(buf, offset, keyLen)
			offset = offset + keyLen

			local entry = newPose()
			entry.Parent = keyframe

			-- Read Name string (length-prefixed)
			local nameLen = buffer.readu32(buf, offset)
			offset = offset + 4
			entry.Name = buffer.readstring(buf, offset, nameLen)
			offset = offset + nameLen

			-- Read Parent Name (length-prefixed)
			local parentNameLen = buffer.readu32(buf, offset)
			offset = offset + 4
			local parentName = buffer.readstring(buf, offset, parentNameLen)
			offset = offset + parentNameLen

			-- Store parent association
			if ( string.len(parentName) > 0 ) then
				parentMap[entry.Name] = parentName
			end

			-- Read CFrame (12 doubles)
			local x = buffer.readf64(buf, offset)
			offset = offset + 8
			local y = buffer.readf64(buf, offset)
			offset = offset + 8
			local z = buffer.readf64(buf, offset)
			offset = offset + 8
			local r00 = buffer.readf64(buf, offset)
			offset = offset + 8
			local r01 = buffer.readf64(buf, offset)
			offset = offset + 8
			local r02 = buffer.readf64(buf, offset)
			offset = offset + 8
			local r10 = buffer.readf64(buf, offset)
			offset = offset + 8
			local r11 = buffer.readf64(buf, offset)
			offset = offset + 8
			local r12 = buffer.readf64(buf, offset)
			offset = offset + 8
			local r20 = buffer.readf64(buf, offset)
			offset = offset + 8
			local r21 = buffer.readf64(buf, offset)
			offset = offset + 8
			local r22 = buffer.readf64(buf, offset)
			offset = offset + 8
			entry.CFrame = CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)

			-- Read EasingDirection (uint32)
			local easingDirValue = buffer.readu32(buf, offset)
			offset = offset + 4
			entry.EasingDirection = Enum.EasingDirection:FromValue(easingDirValue) :: Enum.EasingDirection

			-- Read EasingStyle string (length-prefixed)
			local easingStyleNameLen = buffer.readu32(buf, offset)
			offset = offset + 4
			entry.EasingStyle = buffer.readstring(buf, offset, easingStyleNameLen)
			offset = offset + easingStyleNameLen

			-- Read Weight (double)
			entry.Weight = buffer.readf64(buf, offset)
			offset = offset + 8

			-- Assign the entry to the PoseMap with the key
			keyframe.PoseMap[key] = entry
			table.insert(keyframe.Poses, entry)
		end

		for bone_name, parent_name in parentMap do
			local child_bone = keyframe.PoseMap[bone_name]
			if ( not child_bone ) then
				continue
			end

			local parent_bone = keyframe.PoseMap[parent_name]
			if ( not parent_bone ) then
				continue
			end

			child_bone.Parent = parent_bone
		end

		-- Add the keyframe to the Keyframes array
		table.insert(data.Keyframes, keyframe)
	end

	return data
end

local function populatePoseMap(rbx_pose: Pose, keyframe: GrooveKeyframe, parent_pose: PosesInterface)
	local easingStyle = poseEasingStyleMap[rbx_pose.EasingStyle] or Enum.EasingStyle.Linear
	local easingDirection = Enum.EasingDirection:FromValue(rbx_pose.EasingDirection.Value) :: Enum.EasingDirection

	local pose = newPose()
	pose.Parent = parent_pose

	-- Copy roblox properties
	pose.Name = rbx_pose.Name
	pose.CFrame = rbx_pose.CFrame
	pose.EasingDirection = easingDirection
	pose.EasingStyle = easingStyle.Name
	pose.Weight = rbx_pose.Weight

	-- Track
	keyframe.PoseMap[pose.Name] = pose
	table.insert(parent_pose.Poses, pose)

	-- Check children
	for _,sub_pose in rbx_pose:GetSubPoses() do
		populatePoseMap(sub_pose :: Pose, keyframe, pose)
	end
end

-- Converts a roblox KeyframeSequence object in to a GrooveKeyframeSequence.
function module:ImportKeyframeSequence(keyframe_sequence: KeyframeSequence) : GrooveKeyframeSequence
	local sequence = newKeyframeSequence()
	sequence.Loop = keyframe_sequence.Loop
	sequence.Name = keyframe_sequence.Name

	-- Create keyframes
	for _,v in pairs(keyframe_sequence:GetKeyframes()) do
		local rbx_keyframe = v :: Keyframe

		-- Create initial keyframe
		local keyframe = newKeyframe()
		keyframe.Time = rbx_keyframe.Time
		keyframe.Name = rbx_keyframe.Name

		-- Populate poses/subposes
		for _,k in pairs(rbx_keyframe:GetPoses()) do
			populatePoseMap(k :: Pose, keyframe, keyframe)
		end

		table.insert(sequence.Keyframes, keyframe)
	end

	-- Sort the keyframes by their Time value.
	table.sort(sequence.Keyframes, function(a, b)
		return a.Time < b.Time
	end)

	return sequence
end

-- Escapes a buffer to a string with \xFF format (2 hex digits)
--[[ If you want to store this to a module you can do:
	```lua
	print(`return "{groove:EncodeBuffer(sequence:Serialize())}"`)
	```
]]
function module:EncodeBuffer(input_buffer: buffer)
	local length = buffer.len(input_buffer)
	local result = {}

	-- Read each byte and convert to escaped hex format
	for i = 0, length - 1 do
		local byte = buffer.readu8(input_buffer, i)
		table.insert(result, string.format("\\x%02X", byte))
	end

	-- Join all escaped sequences into one string
	return table.concat(result)
end

-- Reads an escaped hex string and converts it back in to a buffer
function module:DecodeBuffer(input_string: string)
	-- Create a new buffer with size based on number of \xNN sequences
	local byteCount = #input_string -- Each \xNN is 4 chars representing 1 byte
	local newBuffer = buffer.create(byteCount)

	-- Parse each \xNN sequence and write the byte
	for i = 1, #input_string do
		local byte = input_string:byte(i, i)
		buffer.writeu8(newBuffer, (i - 1), byte) -- Write byte at position
	end

	return newBuffer
end

function module:RegisterEasingStyle(easing_style: string, easing_map: {[Enum.EasingDirection]: (alpha: number)->(number)})
	easingStyleMap[easing_style] = function(alpha: number, easing_direction: Enum.EasingDirection)
		local callback = easing_map[easing_direction]
		if ( callback ) then
			return callback(alpha)
		else
			warn("[GrooveAnimator] Attempt to lerp easing style using undefined easing direction:", easing_style, easing_direction)
			return alpha
		end
	end
end

return module
