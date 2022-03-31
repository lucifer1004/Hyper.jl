const FDInt = Sys.iswindows() ? UInt : Int32
const RawFDRegex = Sys.iswindows() ? r"WindowsRawSocket\((\w+)\)" : r"RawFD\((\d+)\)"
const WSAEWOULDBLOCK = Int32(10035)

function getrawfd(socket)
    if !isopen(socket)
        return -1
    end

    m = match(RawFDRegex, repr(socket))
    rawfd = parse(FDInt, m.captures[1])
    return rawfd
end


function handle(fd::FDInt)
    if Sys.iswindows()
        return Base.WindowsRawSocket(Base.bitcast(Ptr{Cvoid}, fd))
    else
        return RawFD(fd)
    end
end

mutable struct ConnData
    fd::FDInt
    io::IO # To protect the socket against GC
    read_waker::Union{Waker,Nothing}
    write_waker::Union{Waker,Nothing}
end

@enum ExampleType EXAMPLE_NOT_SET EXAMPLE_HANDSHAKE EXAMPLE_SEND EXAMPLE_RESP_BODY

function read_cb!(conn, ctx::Context, buf::AbstractVector{UInt8}, buf_len::UInt64)
    if Sys.iswindows()
        ret = ccall(
            :recv,
            Int32,
            (UInt, Ptr{UInt8}, Int32, Int32),
            conn.fd,
            pointer(buf),
            Int32(buf_len),
            0,
        )
    else
        ret = ccall(
            :read,
            Int32,
            (Int32, Ptr{UInt8}, UInt64),
            conn.fd,
            pointer(buf),
            UInt64(buf_len),
        )
    end

    if ret < 0
        errno = Sys.iswindows() ? ccall(:WSAGetLastError, Int32, ()) : Libc.errno()

        if (Sys.iswindows() && errno == WSAEWOULDBLOCK) ||
           (!Sys.iswindows() && errno == Libc.EAGAIN)
            if !isnothing(conn.read_waker)
                Hyper.free!(conn.read_waker)
            end
            conn.read_waker = Waker(ctx)
            return HYPER_IO_PENDING
        else
            return HYPER_IO_ERROR
        end
    else
        return ret
    end
end

function write_cb!(conn, ctx::Context, buf::AbstractVector{UInt8}, buf_len::Integer)
    if Sys.iswindows()
        ret = ccall(
            :send,
            Int32,
            (UInt, Ptr{UInt8}, Int32, Int32),
            conn.fd,
            pointer(buf),
            Int32(buf_len),
            0,
        )
    else
        ret = ccall(
            :write,
            Int32,
            (Int32, Ptr{UInt8}, UInt64),
            conn.fd,
            pointer(buf),
            UInt64(buf_len),
        )
    end

    if ret < 0
        errno = Sys.iswindows() ? ccall(:WSAGetLastError, Int32, ()) : Libc.errno()

        if (Sys.iswindows() && errno == WSAEWOULDBLOCK) ||
           (!Sys.iswindows() && errno == Libc.EAGAIN)
            if !isnothing(conn.write_waker)
                Hyper.free!(conn.write_waker)
            end
            conn.write_waker = Waker(ctx)
            return HYPER_IO_PENDING
        else
            return HYPER_IO_ERROR
        end
    else
        return ret
    end
end

function free!(conn::ConnData)
    if !isnothing(conn.read_waker)
        Hyper.free!(conn.read_waker)
    end
    conn.read_waker = nothing

    if !isnothing(conn.write_waker)
        Hyper.free!(conn.write_waker)
    end
    conn.write_waker = nothing

    close(conn.io)
end
