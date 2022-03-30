using Hyper
using Sockets
using StringViews
using FileWatching

const FDInt = Sys.iswindows() ? UInt : Int32
const RawFDRegex = Sys.iswindows() ? r"WindowsRawSocket\((\w+)\)" : r"RawFD\((\d+)\)"
const WSAEWOULDBLOCK = Int32(10035)

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

function getrawfd(socket)
    if !isopen(socket)
        return -1
    end

    m = match(RawFDRegex, repr(socket))
    rawfd = parse(FDInt, m.captures[1])
    return rawfd
end

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

        if (Sys.iswindows() && errno == WSAEWOULDBLOCK) || (!Sys.iswindows() && errno == Libc.EAGAIN)
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

        if (Sys.iswindows() && errno == WSAEWOULDBLOCK) || (!Sys.iswindows() && errno == Libc.EAGAIN)
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

function print_each_chunk(userdata, buf::Buf)
    print(StringView(buf))
    return HYPER_ITER_CONTINUE
end

@enum ExampleType EXAMPLE_NOT_SET EXAMPLE_HANDSHAKE EXAMPLE_SEND EXAMPLE_RESP_BODY

function main()
    host = length(ARGS) > 0 ? ARGS[1] : "httpbin.org"
    port = length(ARGS) > 1 ? parse(Int, ARGS[2]) : 80
    path = length(ARGS) > 2 ? ARGS[3] : "/"

    println("connecting to port $port on $host...")
    socket = connect(host, port)
    rawfd = getrawfd(socket)
    conn = ConnData(rawfd, socket, nothing, nothing)
    io = HyperIO()
    io.userdata = conn
    io.read = read_cb!
    io.write = write_cb!

    println("http handshake (hyper v$(Hyper.version())) ...")

    executor = Executor()
    opts = ClientconnOptions()
    exec!(opts, executor)

    hs = handshake!(io, opts)
    hs.userdata = EXAMPLE_HANDSHAKE
    push!(executor, hs)

    while true
        while true
            task = poll!(executor)

            if isnothing(task)
                break
            end

            task_type = task.userdata
            if task_type == EXAMPLE_HANDSHAKE
                if task.type == Hyper.TASK_ERROR
                    @error task.value
                    return
                end

                @assert task.type == Hyper.TASK_CLIENTCONN

                println("preparing http request ...")
                client = task.value
                Hyper.free!(task)

                req = Request()
                req.method = "GET"
                req.uri = path

                headers = req.headers
                headers.Host = host

                send_task = send!(client, req)
                send_task.userdata = EXAMPLE_SEND

                println("sending ...")
                push!(executor, send_task)
                Hyper.free!(client)

                break
            elseif task_type == EXAMPLE_SEND
                if task.type == Hyper.TASK_ERROR
                    @error task.value
                    return
                end

                @assert task.type == Hyper.TASK_RESPONSE

                resp = task.value
                Hyper.free!(task)

                http_status = resp.status
                reason = resp.reason

                println("Response Status: $http_status $reason")
                headers = resp.headers
                println(headers)

                body = resp.body
                foreach_task = foreach!(body, print_each_chunk)
                foreach_task.userdata = EXAMPLE_RESP_BODY
                push!(executor, foreach_task)
                Hyper.free!(resp)

                break
            elseif task_type == EXAMPLE_RESP_BODY
                if task.type == Hyper.TASK_ERROR
                    @error task.value
                    return
                end

                @assert task.type == Hyper.TASK_EMPTY
                println(" -- Done! -- ")

                Hyper.free!(task)
                Hyper.free!(executor)
                free!(conn)

                return 0
            elseif task_type == EXAMPLE_NOT_SET
                Hyper.free!(task)
                break
            else
                @error "Unknown task type"
                return
            end
        end

        result = poll_fd(handle(conn.fd); readable = true, writable = true)

        if result.readable && !isnothing(conn.read_waker)
            wake!(conn.read_waker)
            conn.read_waker = nothing
        end

        if result.writable && !isnothing(conn.write_waker)
            wake!(conn.write_waker)
            conn.write_waker = nothing
        end
    end
end

main()
