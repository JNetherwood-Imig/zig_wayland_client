// 
// Copyright 2016 The Chromium Authors.
// Copyright 2017 Intel Corporation
// Copyright 2018 Collabora, Ltd
// Copyright 2021 Simon Ser
// 
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice (including the next
// paragraph) shall be included in all copies or substantial portions of the
// Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
// 
//! 
//! This protocol allows clients to request explicit synchronization for
//! buffers. It is tied to the Linux DRM synchronization object framework.
//! 
//! Synchronization refers to co-ordination of pipelined operations performed
//! on buffers. Most GPU clients will schedule an asynchronous operation to
//! render to the buffer, then immediately send the buffer to the compositor
//! to be attached to a surface.
//! 
//! With implicit synchronization, ensuring that the rendering operation is
//! complete before the compositor displays the buffer is an implementation
//! detail handled by either the kernel or userspace graphics driver.
//! 
//! By contrast, with explicit synchronization, DRM synchronization object
//! timeline points mark when the asynchronous operations are complete. When
//! submitting a buffer, the client provides a timeline point which will be
//! waited on before the compositor accesses the buffer, and another timeline
//! point that the compositor will signal when it no longer needs to access the
//! buffer contents for the purposes of the surface commit.
//! 
//! Linux DRM synchronization objects are documented at:
//! https://dri.freedesktop.org/docs/drm/gpu/drm-mm.html#drm-sync-objects
//! 
//! Warning! The protocol described in this file is currently in the testing
//! phase. Backward compatible changes may be added together with the
//! corresponding interface version bump. Backward incompatible changes can
//! only be done by creating a new major version of the extension.
//! 
const std = @import("std");
const Object = @import("Object.zig");
const Surface = @import("wayland.zig").Surface;
/// 
/// This global is a factory interface, allowing clients to request
/// explicit synchronization for buffers on a per-surface basis.
/// 
/// See wp_linux_drm_syncobj_surface_v1 for more information.
/// 
pub const PLinuxDrmSyncobjManagerV1 = struct {
	proxy: Object,
	pub const interface = "wp_linux_drm_syncobj_manager_v1";
	pub const event0_index: u32 = 0;
	/// 
	/// Destroy this explicit synchronization factory object. Other objects
	/// shall not be affected by this request.
	/// 
	pub fn destroy(
		self: @This(),
	) void {
		self.proxy.sendDestroyRequest(0, .{
		});
	}
	/// 
	/// Instantiate an interface extension for the given wl_surface to provide
	/// explicit synchronization.
	/// 
	/// If the given wl_surface already has an explicit synchronization object
	/// associated, the surface_exists protocol error is raised.
	/// 
	/// Graphics APIs, like EGL or Vulkan, that manage the buffer queue and
	/// commits of a wl_surface themselves, are likely to be using this
	/// extension internally. If a client is using such an API for a
	/// wl_surface, it should not directly use this extension on that surface,
	/// to avoid raising a surface_exists protocol error.
	/// 
	pub fn getSurface(
		self: @This(),
		/// the surface
		surface: Surface,
	) !PLinuxDrmSyncobjSurfaceV1 {
		return try self.proxy.sendCreateRequest(PLinuxDrmSyncobjSurfaceV1, self.proxy.display, 1, .{
			Object.Arg{ .new_id = .{
			}},
			Object.Arg{ .object = surface },
		});
	}
	/// 
	/// Import a DRM synchronization object timeline.
	/// 
	/// If the FD cannot be imported, the invalid_timeline error is raised.
	/// 
	pub fn importTimeline(
		self: @This(),
		/// drm_syncobj file descriptor
		fd: std.posix.fd_t,
	) !PLinuxDrmSyncobjTimelineV1 {
		return try self.proxy.sendCreateRequest(PLinuxDrmSyncobjTimelineV1, self.proxy.display, 2, .{
			Object.Arg{ .new_id = .{
			}},
			Object.Arg{ .fd = fd },
		});
	}
	pub const Error = enum(u32) {
		/// the surface already has a synchronization object associated
		surface_exists = 0,
		/// the timeline object could not be imported
		invalid_timeline = 1,
	};
};
/// 
/// This object represents an explicit synchronization object timeline
/// imported by the client to the compositor.
/// 
pub const PLinuxDrmSyncobjTimelineV1 = struct {
	proxy: Object,
	pub const interface = "wp_linux_drm_syncobj_timeline_v1";
	pub const event0_index: u32 = 0;
	/// 
	/// Destroy the synchronization object timeline. Other objects are not
	/// affected by this request, in particular timeline points set by
	/// set_acquire_point and set_release_point are not unset.
	/// 
	pub fn destroy(
		self: @This(),
	) void {
		self.proxy.sendDestroyRequest(0, .{
		});
	}
};
/// 
/// This object is an add-on interface for wl_surface to enable explicit
/// synchronization.
/// 
/// Each surface can be associated with only one object of this interface at
/// any time.
/// 
/// Explicit synchronization is guaranteed to be supported for buffers
/// created with any version of the linux-dmabuf protocol. Compositors are
/// free to support explicit synchronization for additional buffer types.
/// If at surface commit time the attached buffer does not support explicit
/// synchronization, an unsupported_buffer error is raised.
/// 
/// As long as the wp_linux_drm_syncobj_surface_v1 object is alive, the
/// compositor may ignore implicit synchronization for buffers attached and
/// committed to the wl_surface. The delivery of wl_buffer.release events
/// for buffers attached to the surface becomes undefined.
/// 
/// Clients must set both acquire and release points if and only if a
/// non-null buffer is attached in the same surface commit. See the
/// no_buffer, no_acquire_point and no_release_point protocol errors.
/// 
/// If at surface commit time the acquire and release DRM syncobj timelines
/// are identical, the acquire point value must be strictly less than the
/// release point value, or else the conflicting_points protocol error is
/// raised.
/// 
pub const PLinuxDrmSyncobjSurfaceV1 = struct {
	proxy: Object,
	pub const interface = "wp_linux_drm_syncobj_surface_v1";
	pub const event0_index: u32 = 0;
	/// 
	/// Destroy this surface synchronization object.
	/// 
	/// Any timeline point set by this object with set_acquire_point or
	/// set_release_point since the last commit may be discarded by the
	/// compositor. Any timeline point set by this object before the last
	/// commit will not be affected.
	/// 
	pub fn destroy(
		self: @This(),
	) void {
		self.proxy.sendDestroyRequest(0, .{
		});
	}
	/// 
	/// Set the timeline point that must be signalled before the compositor may
	/// sample from the buffer attached with wl_surface.attach.
	/// 
	/// The 64-bit unsigned value combined from point_hi and point_lo is the
	/// point value.
	/// 
	/// The acquire point is double-buffered state, and will be applied on the
	/// next wl_surface.commit request for the associated surface. Thus, it
	/// applies only to the buffer that is attached to the surface at commit
	/// time.
	/// 
	/// If an acquire point has already been attached during the same commit
	/// cycle, the new point replaces the old one.
	/// 
	/// If the associated wl_surface was destroyed, a no_surface error is
	/// raised.
	/// 
	/// If at surface commit time there is a pending acquire timeline point set
	/// but no pending buffer attached, a no_buffer error is raised. If at
	/// surface commit time there is a pending buffer attached but no pending
	/// acquire timeline point set, the no_acquire_point protocol error is
	/// raised.
	/// 
	pub fn setAcquirePoint(
		self: @This(),
		timeline: PLinuxDrmSyncobjTimelineV1,
		/// high 32 bits of the point value
		point_hi: u32,
		/// low 32 bits of the point value
		point_lo: u32,
	) !void {
		_ = try self.proxy.sendRequest(null, 1, .{
			Object.Arg{ .object = timeline },
			Object.Arg{ .uint = point_hi },
			Object.Arg{ .uint = point_lo },
		});
	}
	/// 
	/// Set the timeline point that must be signalled by the compositor when it
	/// has finished its usage of the buffer attached with wl_surface.attach
	/// for the relevant commit.
	/// 
	/// Once the timeline point is signaled, and assuming the associated buffer
	/// is not pending release from other wl_surface.commit requests, no
	/// additional explicit or implicit synchronization with the compositor is
	/// required to safely re-use the buffer.
	/// 
	/// Note that clients cannot rely on the release point being always
	/// signaled after the acquire point: compositors may release buffers
	/// without ever reading from them. In addition, the compositor may use
	/// different presentation paths for different commits, which may have
	/// different release behavior. As a result, the compositor may signal the
	/// release points in a different order than the client committed them.
	/// 
	/// Because signaling a timeline point also signals every previous point,
	/// it is generally not safe to use the same timeline object for the
	/// release points of multiple buffers. The out-of-order signaling
	/// described above may lead to a release point being signaled before the
	/// compositor has finished reading. To avoid this, it is strongly
	/// recommended that each buffer should use a separate timeline for its
	/// release points.
	/// 
	/// The 64-bit unsigned value combined from point_hi and point_lo is the
	/// point value.
	/// 
	/// The release point is double-buffered state, and will be applied on the
	/// next wl_surface.commit request for the associated surface. Thus, it
	/// applies only to the buffer that is attached to the surface at commit
	/// time.
	/// 
	/// If a release point has already been attached during the same commit
	/// cycle, the new point replaces the old one.
	/// 
	/// If the associated wl_surface was destroyed, a no_surface error is
	/// raised.
	/// 
	/// If at surface commit time there is a pending release timeline point set
	/// but no pending buffer attached, a no_buffer error is raised. If at
	/// surface commit time there is a pending buffer attached but no pending
	/// release timeline point set, the no_release_point protocol error is
	/// raised.
	/// 
	pub fn setReleasePoint(
		self: @This(),
		timeline: PLinuxDrmSyncobjTimelineV1,
		/// high 32 bits of the point value
		point_hi: u32,
		/// low 32 bits of the point value
		point_lo: u32,
	) !void {
		_ = try self.proxy.sendRequest(null, 2, .{
			Object.Arg{ .object = timeline },
			Object.Arg{ .uint = point_hi },
			Object.Arg{ .uint = point_lo },
		});
	}
	pub const Error = enum(u32) {
		/// the associated wl_surface was destroyed
		no_surface = 1,
		/// the buffer does not support explicit synchronization
		unsupported_buffer = 2,
		/// no buffer was attached
		no_buffer = 3,
		/// no acquire timeline point was set
		no_acquire_point = 4,
		/// no release timeline point was set
		no_release_point = 5,
		/// acquire and release timeline points are in conflict
		conflicting_points = 6,
	};
};
