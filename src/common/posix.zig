const std = @import("std");
const linux = std.os.linux;
const system = linux;

pub const Errno = enum(u32) {
    success = 0,
    operation_not_permitted = 1,
    no_such_file_or_directory = 2,
    no_such_process = 3,
    interrupted_system_call = 4,
    input_output_error = 5,
    no_such_device_or_address = 6,
    argument_list_too_long = 7,
    exec_format_error = 8,
    bad_file_descriptor = 9,
    no_child_processes = 10,
    resource_temporarily_unavailable = 11,
    cannot_allocate_memory = 12,
    permission_denied = 13,
    bad_address = 14,
    block_device_required = 15,
    device_or_resource_busy = 16,
    file_exists = 17,
    invalid_cross_device_link = 18,
    no_such_device = 19,
    not_a_directory = 20,
    is_a_directory = 21,
    invalid_argument = 22,
    too_many_open_files_in_system = 23,
    too_many_open_files = 24,
    inappropriate_ioctl_for_device = 25,
    text_file_busy = 26,
    file_too_large = 27,
    no_space_left_on_device = 28,
    illegal_seek = 29,
    read_only_file_system = 30,
    too_many_links = 31,
    broken_pipe = 32,
    numerical_argument_out_of_domain = 33,
    numerical_result_out_of_range = 34,
    resource_deadlock_avoided = 35,
    file_name_too_long = 36,
    no_locks_available = 37,
    function_not_implemented = 38,
    directory_not_empty = 39,
    too_many_levels_of_symbolic_links = 40,
    no_message_of_desired_type = 42,
    identifier_removed = 43,
    channel_number_out_of_range = 44,
    level_2_not_synchronized = 45,
    level_3_halted = 46,
    level_3_reset = 47,
    link_number_out_of_range = 48,
    protocol_driver_not_attached = 49,
    no_csi_structure_available = 50,
    level_2_halted = 51,
    invalid_exchange = 52,
    invalid_request_descriptor = 53,
    exchange_full = 54,
    no_anode = 55,
    invalid_request_code = 56,
    invalid_slot = 57,
    bad_font_file_format = 59,
    device_not_a_stream = 60,
    no_data_available = 61,
    timer_expired = 62,
    out_of_streams_resources = 63,
    machine_is_not_on_the_network = 64,
    package_not_installed = 65,
    object_is_remote = 66,
    link_has_been_severed = 67,
    advertise_error = 68,
    srmount_error = 69,
    communication_error_on_send = 70,
    protocol_error = 71,
    multihop_attempted = 72,
    rfs_specific_error = 73,
    bad_message = 74,
    value_too_large_for_defined_data_type = 75,
    name_not_unique_on_network = 76,
    file_descriptor_in_bad_state = 77,
    remote_address_changed = 78,
    cannot_access_needed_shared_library = 79,
    accessing_corrupted_shared_library = 80,
    lib_section_corrupted = 81,
    too_many_shared_libraries = 82,
    cannot_exec_shared_library_directly = 83,
    invalid_or_incomplete_multibyte_or_wide_character = 84,
    interrupted_call_should_be_restarted = 85,
    streams_pipe_error = 86,
    too_many_users = 87,
    socket_operation_on_non_socket = 88,
    destination_address_required = 89,
    message_too_long = 90,
    protocol_wrong_type_for_socket = 91,
    protocol_not_available = 92,
    protocol_not_supported = 93,
    socket_type_not_supported = 94,
    operation_not_supported = 95,
    protocol_family_not_supported = 96,
    address_family_not_supported_by_protocol = 97,
    address_already_in_use = 98,
    cannot_assign_requested_address = 99,
    network_is_down = 100,
    network_is_unreachable = 101,
    network_dropped_connection_on_reset = 102,
    software_caused_connection_abort = 103,
    connection_reset_by_peer = 104,
    no_buffer_space_available = 105,
    transport_endpoint_already_connected = 106,
    transport_endpoint_not_connected = 107,
    cannot_send_after_transport_endpoint_shutdown = 108,
    too_many_references = 109,
    connection_timed_out = 110,
    connection_refused = 111,
    host_is_down = 112,
    no_route_to_host = 113,
    operation_already_in_progress = 114,
    operation_now_in_progress = 115,
    stale_file_handle = 116,
    structure_needs_cleaning = 117,
    not_a_xenix_named_type_file = 118,
    no_xenix_semaphores_available = 119,
    is_a_named_type_file = 120,
    remote_io_error = 121,
    disk_quota_exceeded = 122,
    no_medium_found = 123,
    wrong_medium_type = 124,
    operation_canceled = 125,
    required_key_not_available = 126,
    key_has_expired = 127,
    key_has_been_revoked = 128,
    key_was_rejected_by_service = 129,

    pub fn get(ret: usize) Errno {
        const signed: isize = @bitCast(ret);
        const int = if (signed > -4096 and signed < 0) -signed else 0;
        return @enumFromInt(int);
    }
};

pub const Error = error{
    OperationNotPermitted,
    NoSuchFileOrDirectory,
    NoSuchProcess,
    InterruptedSystemCall,
    InputOutputError,
    NoSuchDeviceOrAddress,
    ArgumentListTooLong,
    ExecFormatError,
    BadFileDescriptor,
    NoChildProcesses,
    ResourceTemporarilyUnavailable,
    CannotAllocateMemory,
    PermissionDenied,
    BadAddress,
    BlockDeviceRequired,
    DeviceOrResourceBusy,
    FileExists,
    InvalidCrossDeviceLink,
    NoSuchDevice,
    NotADirectory,
    IsADirectory,
    InvalidArgument,
    TooManyOpenFilesInSystem,
    TooManyOpenFiles,
    InappropriateIoctlForDevice,
    TextFileBusy,
    FileTooLarge,
    NoSpaceLeftOnDevice,
    IllegalSeek,
    ReadOnlyFileSystem,
    TooManyLinks,
    BrokenPipe,
    NumericalArgumentOutOfDomain,
    NumericalResultOutOfRange,
    ResourceDeadlockAvoided,
    FileNameTooLong,
    NoLocksAvailable,
    FunctionNotImplemented,
    DirectoryNotEmpty,
    TooManyLevelsOfSymbolicLinks,
    NoMessageOfDesiredType,
    IdentifierRemoved,
    ChannelNumberOutOfRange,
    Level2NotSynchronized,
    Level3Halted,
    Level3Reset,
    LinkNumberOutOfRange,
    ProtocolDriverNotAttached,
    NoCsiStructureAvailable,
    Level2Halted,
    InvalidExchange,
    InvalidRequestDescriptor,
    ExchangeFull,
    NoAnode,
    InvalidRequestCode,
    InvalidSlot,
    BadFontFileFormat,
    DeviceNotAStream,
    NoDataAvailable,
    TimerExpired,
    OutOfStreamsResources,
    MachineIsNotOnTheNetwork,
    PackageNotInstalled,
    ObjectIsRemote,
    LinkHasBeenSevered,
    AdvertiseError,
    SrmountError,
    CommunicationErrorOnSend,
    ProtocolError,
    MultihopAttempted,
    RfsSpecificError,
    BadMessage,
    ValueTooLargeForDefinedDataType,
    NameNotUniqueOnNetwork,
    FileDescriptorInBadState,
    RemoteAddressChanged,
    CannotAccessNeededSharedLibrary,
    AccessingCorruptedSharedLibrary,
    LibSectionCorrupted,
    TooManySharedLibraries,
    CannotExecSharedLibraryDirectly,
    InvalidOrIncompleteMultibyteOrWideCharacter,
    InterruptedCallShouldBeRestarted,
    StreamsPipeError,
    TooManyUsers,
    SocketOperationOnNonSocket,
    DestinationAddressRequired,
    MessageTooLong,
    ProtocolWrongTypeForSocket,
    ProtocolNotAvailable,
    ProtocolNotSupported,
    SocketTypeNotSupported,
    OperationNotSupported,
    ProtocolFamilyNotSupported,
    AddressFamilyNotSupportedByProtocol,
    AddressAlreadyInUse,
    CannotAssignRequestedAddress,
    NetworkIsDown,
    NetworkIsUnreachable,
    NetworkDroppedConnectionOnReset,
    SoftwareCausedConnectionAbort,
    ConnectionResetByPeer,
    NoBufferSpaceAvailable,
    TransportEndpointAlreadyConnected,
    TransportEndpointNotConnected,
    CannotSendAfterTransportEndpointShutdown,
    TooManyReferences,
    ConnectionTimedOut,
    ConnectionRefused,
    HostIsDown,
    NoRouteToHost,
    OperationAlreadyInProgress,
    OperationNowInProgress,
    StaleFileHandle,
    StructureNeedsCleaning,
    NotAXenixNamedTypeFile,
    NoXenixSemaphoresAvailable,
    IsANamedTypeFile,
    RemoteIoError,
    DiskQuotaExceeded,
    NoMediumFound,
    WrongMediumType,
    OperationCanceled,
    RequiredKeyNotAvailable,
    KeyHasExpired,
    KeyHasBeenRevoked,
    KeyWasRejectedByService,
};

pub const Fd = i32;

pub const AccessMode = enum(u2) {
    read_only,
    write_only,
    read_write,
};

pub const OpenOptions = packed struct(u32) {
    access_mode: AccessMode = .read_only,
    _2: u4 = 0,
    create: bool = false,
    exclusive: bool = false,
    no_controlling_tty: bool = false,
    truncate: bool = false,
    append: bool = false,
    nonblocking: bool = false,
    data_synchronized_io: bool = false,
    asynchronous_io: bool = false,
    direct_io: bool = false,
    _15: u1 = 0,
    ensure_directory: bool = false,
    no_follow_symlinks: bool = false,
    no_access_time: bool = false,
    close_on_exec: bool = false,
    file_synchronized: bool = false,
    path_only: bool = false,
    create_temp: bool = false,
    _: u9 = 0,
};

pub const FileMode = packed struct(u3) {
    read: bool = false,
    write: bool = false,
    execute: bool = false,

    pub const all: u3 = 0b111;
};

pub const FileType = enum(u4) {
    none = 0b0000,
    fifo = 0b0001,
    character_device = 0b0010,
    directory = 0b0100,
    block_device = 0b0110,
    regular = 0b1000,
    link = 0b1010,
    socket = 0b1100,
};

pub const FileStatus = packed struct(u32) {
    other_mode: FileMode = .{},
    group_mode: FileMode = .{},
    owner_mode: FileMode = .{},
    sticky: bool = false,
    set_gid: bool = false,
    set_uid: bool = false,
    type: FileType = .none,
    _: u16 = 0,
};

pub const OpenError = error{
    PermissionDenied,
    BadFileDescriptor,
    DeviceOrResourceBusy,
    DiskQuotaExceeded,
    FileExists,
    BadAddress,
    FileTooLarge,
    InterruptedSystemCall,
    InvalidArgument,
    IsADirectory,
    TooManyLevelsOfSymbolicLinks,
    TooManyOpenFiles,
    FileNameTooLong,
    TooManyOpenFilesInSystem,
    NoSuchDevice,
    NoSuchFileOrDirectory,
    CannotAllocateMemory,
    NoSpaceLeftOnDevice,
    NotADirectory,
    NoSuchDeviceOrAddress,
    OperationNotSupported,
    ValueTooLargeForDefinedDataType,
    OperationNotPermitted,
    ReadOnlyFileSystem,
    TextFileBusy,
    ResourceTemporarilyUnavailable,
};

pub fn open(path: [:0]const u8, options: OpenOptions, status: FileStatus) OpenError!Fd {
    while (true) {
        const ret = system.open(path, @bitCast(options), @intCast(@as(u32, @bitCast(status))));
        const err = Errno.get(ret);
        switch (err) {
            .success => return @intCast(ret),

            .interrupted_system_call => continue,

            .permission_denied => return error.PermissionDenied,
            .device_or_resource_busy => return error.DeviceOrResourceBusy,
            .disk_quota_exceeded => return error.DiskQuotaExceeded,
            .file_exists => return error.FileExists,
            .bad_address => return error.BadAddress,
            .file_too_large => return error.FileTooLarge,
            .invalid_argument => return error.InvalidArgument,
            .is_a_directory => return error.IsADirectory,
            .too_many_levels_of_symbolic_links => return error.TooManyLevelsOfSymbolicLinks,
            .too_many_open_files => return error.TooManyOpenFiles,
            .file_name_too_long => return error.FileNameTooLong,
            .too_many_open_files_in_system => return error.TooManyOpenFilesInSystem,
            .no_such_device => return error.NoSuchDevice,
            .no_such_file_or_directory => return error.NoSuchFileOrDirectory,
            .cannot_allocate_memory => return error.CannotAllocateMemory,
            .no_space_left_on_device => return error.NoSpaceLeftOnDevice,
            .no_such_device_or_address => return error.NoSuchDeviceOrAddress,
            .operation_not_supported => return error.OperationNotSupported,
            .value_too_large_for_defined_data_type => return error.ValueTooLargeForDefinedDataType,
            .operation_not_permitted => return error.OperationNotPermitted,
            .read_only_file_system => return error.ReadOnlyFileSystem,
            .text_file_busy => return error.TextFileBusy,
            .resource_temporarily_unavailable => return error.ResourceTemporarilyUnavailable,

            else => unreachable,
        }
    }
}

pub fn close(fd: Fd) void {
    _ = system.close(fd);
}

test "open/close" {
    const fd = try open("/dev/dri/card1", .{}, .{});
    defer close(fd);
    std.debug.print("GPU fd is {d}\n", .{fd});
}

pub const FcntlCommand = enum(u32) {
    dupfd = 0,
    get_fd_flags = 1,
    set_fd_flags = 2,
    get_status_flags = 3,
    set_status_flags = 4,
    get_locking_info = 5,
    set_locking_info = 6,
    set_locking_info_blocking = 7,
    set_own = 8,
    get_own = 9,
    set_sig = 10,
    get_sig = 11,
    set_own_ex = 15,
    get_own_ex = 16,
    get_owner_uids = 17,

    set_lease = 1024,
    get_lease = 1025,
    notify = 1026,
    dup_fd_query = 1027,
    created_query = 1028,

    dupfd_cloexec = 1030,

    set_pipe_page_size = 1031,
    get_pipe_page_size = 1032,
    add_seals = 1033,
    get_seals = 1034,
    get_rw_hint = 1035,
    set_rw_hint = 1036,
    get_file_rw_hint = 1037,
    set_file_rw_hint = 1038,

    read_lock = 0,
    write_lock = 1,
    unlock = 2,

    pub const fd_cloexec = 1;
};

pub const FcntlError = error{
    OperationNotPermitted,
    NoSuchProcess,
    InterruptedSystemCall,
    BadFileDescriptor,
    ResourceTemporarilyUnavailable,
    PermissionDenied,
    InvalidArgument,
    TooManyOpenFiles,
    ResourceDeadlockAvoided,
    NoLocksAvailable,
    ValueTooLargeForDefinedDataType,
};

pub fn fcntl(fd: Fd, cmd: FcntlCommand, arg: usize) FcntlError!usize {
    const ret = system.fcntl(fd, @intFromEnum(cmd), arg);
    const err = Errno.get(ret);
    return switch (err) {
        .success => ret,
        .operation_not_permitted => error.OperationNotPermitted,
        .no_such_process => error.NoSuchProcess,
        .interrupted_system_call => error.InterruptedSystemCall,
        .bad_file_descriptor => error.BadFileDescriptor,
        .resource_temporarily_unavailable => error.ResourceTemporarilyUnavailable,
        .permission_denied => error.PermissionDenied,
        .invalid_argument => error.InvalidArgument,
        .too_many_open_files => error.TooManyOpenFiles,
        .resource_deadlock_avoided => error.ResourceDeadlockAvoided,
        .no_locks_available => error.NoLocksAvailable,
        .value_too_large_for_defined_data_type => error.ValueTooLargeForDefinedDataType,
        else => unreachable,
    };
}

// pub const Epoll = struct {
//     handle: Fd,

//     pub const CreateError = posix.EpollCreateError;
//     pub inline fn create(flags: u32) CreateError!Epoll {
//         return .{ .handle = try posix.epoll_create1(flags) };
//     }

//     pub inline fn close(self: Epoll) void {
//         posix.close(self.handle);
//     }

//     pub const Ctl = enum(u2) {
//         add = linux.EPOLL.CTL_ADD,
//         del = linux.EPOLL.CTL_DEL,
//         mod = linux.EPOLL.CTL_MOD,
//     };

//     pub const Events = packed struct(u32) {
//         in: bool = false,
//         pri: bool = false,
//         out: bool = false,
//         err: bool = false,
//         hup: bool = false,
//         rdnorm: bool = false,
//         wrnorm: bool = false,
//         rdband: bool = false,
//         wrband: bool = false,
//         msg: bool = false,
//         _: u22 = 0,
//     };

//     pub const Data = extern union {
//         ptr: usize,
//         fd: i32,
//         u32: u32,
//         u64: u64,
//     };

//     pub const Event = extern struct {
//         events: Events,
//         data: Data align(switch (@import("builtin").cpu.arch) {
//             .x86_64 => 4,
//             else => @alignOf(Data),
//         }),
//     };

//     pub const CtlError = posix.EpollCtlError;
//     pub inline fn ctl(
//         self: Epoll,
//         op: Ctl,
//         fd: Fd,
//         event: ?Event,
//     ) CtlError!void {
//         var ev = event;
//         return try posix.epoll_ctl(
//             self.handle,
//             @intFromEnum(op),
//             fd,
//             @ptrCast(&ev),
//         );
//     }

//     pub const WaitError = error{
//         BadAddress,
//         InterruptedSystemCall,
//         Unexpected,
//     };
//     pub inline fn wait(
//         self: Epoll,
//         events: []Event,
//         timeout: i32,
//     ) WaitError!usize {
//         const ret = linux.epoll_wait(
//             self.handle,
//             @ptrCast(events.ptr),
//             @intCast(events.len),
//             timeout,
//         );
//         return switch (posix.errno(ret)) {
//             .SUCCESS => ret,
//             .FAULT => error.BadAddress,
//             .INTR => error.InterruptedSystemCall,
//             .BADF, .INVAL => unreachable,
//             else => error.Unexpected,
//         };
//     }
// };

// pub const Pipe = struct {
//     handle: [2]Fd,

//     pub const CreateError = posix.PipeError;
//     pub inline fn create() CreateError!Pipe {
//         return .{ .handle = try posix.pipe() };
//     }

//     pub inline fn close(self: Pipe) void {
//         for (self.handle) |fd| posix.close(fd);
//     }

//     pub inline fn getReadFd(self: Pipe) Fd {
//         return self.handle[0];
//     }

//     pub inline fn getWriteFd(self: Pipe) Fd {
//         return self.handle[1];
//     }
// };

// const SIG = linux.SIG;

// pub const Sig = enum(u32) {
//     hangup = SIG.HUP,
//     interrupt = SIG.INT,
//     quit = SIG.QUIT,
//     illegal_instruction = SIG.ILL,
//     trap = SIG.TRAP,
//     aborted = SIG.ABRT,
//     bus_error = SIG.BUS,
//     floating_point_exception = SIG.FPE,
//     kill = SIG.KILL,
//     user_1 = SIG.USR1,
//     segmentation_fault = SIG.SEGV,
//     user_2 = SIG.USR2,
//     broken_pipe = SIG.PIPE,
//     alarm = SIG.ALRM,
//     terminated = SIG.TERM,
//     stack_fault = SIG.STKFLT,
//     child_status_changed = SIG.CHLD,
//     @"continue" = SIG.CONT,
//     stop = SIG.STOP,
//     stop_user = SIG.TSTP,
//     stop_tty_in = SIG.TTIN,
//     stop_tty_out = SIG.TTOU,
//     urgent_io = SIG.URG,
//     cpu_time_limit_exceeded = SIG.XCPU,
//     file_size_limit_exceeded = SIG.XFSZ,
//     virtual_timer_expired = SIG.VTALRM,
//     profiling_timer_expired = SIG.PROF,
//     io_possible = SIG.IO,
//     power_failure = SIG.PWR,
//     bad_syscall = SIG.SYS,
// };

// pub const Signalfd = struct {
//     handle: Fd,

//     pub const Signals = packed struct {
//         hangup: bool = false,
//         interrupt: bool = false,
//         quit: bool = false,
//         illegal_instruction: bool = false,
//         trap: bool = false,
//         aborted: bool = false,
//         bus_error: bool = false,
//         floating_point_exception: bool = false,
//         kill: bool = false,
//         user_1: bool = false,
//         segmentation_fault: bool = false,
//         user_2: bool = false,
//         broken_pipe: bool = false,
//         alarm: bool = false,
//         terminated: bool = false,
//         stack_fault: bool = false,
//         child_status_changed: bool = false,
//         @"continue": bool = false,
//         stop: bool = false,
//         stop_user: bool = false,
//         stop_tty_in: bool = false,
//         stop_tty_out: bool = false,
//         urgent_io: bool = false,
//         cpu_time_limit_exceeded: bool = false,
//         file_size_limit_exceeded: bool = false,
//         virtual_timer_expired: bool = false,
//         profiling_timer_expired: bool = false,
//         io_possible: bool = false,
//         power_failure: bool = false,
//         bad_syscall: bool = false,
//     };

//     pub const CreateError = error{
//         SystemFdQuotaExceeded,
//         SystemResources,
//         ProcessResources,
//         InodeMountFail,
//     };

//     pub fn create(signals: Signals) CreateError!Signalfd {
//         var set: linux.sigset_t = linux.empty_sigset;
//         inline for (@typeInfo(Signals).@"struct".fields) |field|
//             if (@field(signals, field.name))
//                 linux.sigaddset(&set, @intFromEnum(@field(Sig, field.name)));

//         posix.sigprocmask(SIG.BLOCK, &set, null);

//         const fd = posix.signalfd(-1, &set, linux.SFD.NONBLOCK) catch |err|
//             return switch (err) {
//                 error.SystemFdQuotaExceeded => error.SystemFdQuotaExceeded,
//                 error.SystemResources => error.SystemResources,
//                 error.ProcessResources => error.ProcessResources,
//                 error.InodeMountFail => error.InodeMountFail,
//                 error.Unexpected => unreachable,
//             };
//         return .{ .handle = fd };
//     }

//     pub fn close(self: Signalfd) void {
//         posix.close(self.handle);
//     }

//     pub const Siginfo = posix.siginfo_t;

//     pub const ReadError = error{Incomplete} || posix.ReadError;

//     pub fn read(self: Signalfd) ReadError!Siginfo {
//         var info: Siginfo = undefined;
//         const bytes_read = try posix.read(
//             self.handle,
//             @as([*]u8, @ptrCast(@alignCast(&info)))[0..@sizeOf(Siginfo)],
//         );
//         if (bytes_read != @sizeOf(Siginfo)) return error.Incomplete;
//         return info;
//     }
// };

// pub const Poll = struct {
//     pub const Events = packed struct(u16) {
//         in: bool = false,
//         pri: bool = false,
//         out: bool = false,
//         err: bool = false,
//         hup: bool = false,
//         nval: bool = false,
//         rdnorm: bool = false,
//         rdband: bool = false,
//         wrnorm: bool = false,
//         wrband: bool = false,
//         msg: bool = false,
//         remove: bool = false,
//         _: u4 = 0,
//     };

//     pub const Pollfd = extern struct {
//         fd: Fd,
//         events: Events,
//         revents: Events = .{},
//     };

//     pub const Error = posix.PollError;

//     pub fn poll(pfds: []Pollfd, timeout: i32) Error!usize {
//         return try posix.poll(@ptrCast(pfds), timeout);
//     }
// };
