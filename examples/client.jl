using Hyper
using Sockets
using StringViews
using FileWatching

function reset()
    ccall((:reset, "libfdset.so"), Cvoid, ())
end

function set_read(fd)
    ccall((:set_read, "libfdset.so"), Cvoid, (Int32,), fd)
end

function set_write(fd)
    ccall((:set_write, "libfdset.so"), Cvoid, (Int32,), fd)
end

function is_read_set(fd)
    Bool(ccall((:is_read_set, "libfdset.so"), Int32, (Int32,), fd))
end

function is_write_set(fd)
    Bool(ccall((:is_write_set, "libfdset.so"), Int32, (Int32,), fd))
end

function select(fd)
    ccall((:fd_select, "libfdset.so"), Int32, (Int32,), fd)
end

mutable struct ConnData
    fd::Int32
    io::IO # To protect the socket against GC
    read_waker::Union{Waker,Nothing}
    write_waker::Union{Waker,Nothing}
end

function getrawfd(socket)
    if !isopen(socket)
        return -1
    end

    m = match(r"RawFD\((\d+)\)", repr(socket))
    rawfd = parse(Int32, m.captures[1])
    return rawfd
end

function read_cb!(conn, ctx::Context, buf::AbstractVector{UInt8}, buf_len::UInt64)
    @debug "read! called with ctx=$(ctx) and buf_len=$(buf_len)"

    ret = ccall(:read, Int32, (Int32, Ptr{UInt8}, UInt64), conn.fd, pointer(buf), UInt64(buf_len))

    if ret < 0
        @debug "C read error: $(Libc.errno())"
        if Libc.errno() == Libc.EAGAIN
            if !isnothing(conn.read_waker)
                Hyper.free!(conn.read_waker)
            end
            conn.read_waker = Waker(ctx)
            return HYPER_IO_PENDING
        else
            return HYPER_IO_ERROR
        end
    else
        @debug "read $ret bytes"
        return ret
    end
end

function write_cb!(conn, ctx::Context, buf::AbstractVector{UInt8}, buf_len::Integer)
    @debug "write! called with ctx=$(ctx) and buf_len=$(buf_len)"
    @debug "to write: $(StringView(buf))"

    ret = ccall(:write, Int32, (Int32, Ptr{UInt8}, UInt64), conn.fd, pointer(buf), UInt64(buf_len))

    if ret < 0
        @debug "C write error: $(Libc.errno())"
        if Libc.errno() == Libc.EAGAIN
            if !isnothing(conn.read_waker)
                Hyper.free!(conn.read_waker)
            end
            conn.read_waker = Waker(ctx)
            return HYPER_IO_PENDING
        else
            return HYPER_IO_ERROR
        end
    else
        @debug "wrote $ret bytes"
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

    @info conn
    close(conn.socket)
end

function print_each_chunk(userdata, buf::Buf)
    # print(StringView(buf))
    println("Chunk length = $(length(buf))")
    return HYPER_ITER_CONTINUE
end

@enum ExampleType EXAMPLE_NOT_SET EXAMPLE_HANDSHAKE EXAMPLE_SEND EXAMPLE_RESP_BODY

function main()
    host = length(ARGS) > 0 ? ARGS[1] : "httpbin.org"
    port = length(ARGS) > 1 ? parse(Int, ARGS[2]) : 80
    path = length(ARGS) > 2 ? ARGS[3] : "/"

    @info "connecting to port $port on $host..."
    socket = connect(host, port)
    rawfd = getrawfd(socket)
    conn = ConnData(rawfd, socket, nothing, nothing)
    io = HyperIO()
    io.userdata = conn
    io.read = read_cb!
    io.write = write_cb!

    @info "http handshake (hyper v$(Hyper.version())) ..."

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
            @info "Current task: $task_type"
            if task_type == EXAMPLE_HANDSHAKE
                if task.type == Hyper.TASK_ERROR
                    @error "handshake failed"
                    return
                end

                @assert task.type == Hyper.TASK_CLIENTCONN

                @info "preparing http request ..."
                client = task.value
                Hyper.free!(task)

                req = Request()
                req.method = "GET"
                req.uri = path
                req.version = HYPER_HTTP_VERSION_2

                headers = req.headers
                headers.Host = host

                send_task = send!(client, req)
                send_task.userdata = EXAMPLE_SEND

                @info "sending ..."
                push!(executor, send_task)
                Hyper.free!(client)

                break
            elseif task_type == EXAMPLE_SEND
                if task.type == Hyper.TASK_ERROR
                    @error "send failed"
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
                    @error "body error"
                    return
                end

                @assert task.type == Hyper.TASK_EMPTY
                @info " -- Done! -- "

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

        if !isnothing(conn.read_waker)
            wake!(conn.read_waker)
            conn.read_waker = nothing
        end

        if !isnothing(conn.write_waker)
            wake!(conn.write_waker)
            conn.write_waker = nothing
        end

        # result = poll_fd(Sockets.OS_HANDLE(conn.fd); readable=true, writable=true)

        # if result.readable && !isnothing(conn.read_waker)
        #     wake!(conn.read_waker)
        #     conn.read_waker = nothing
        # end

        # if result.writable && !isnothing(conn.write_waker)
        #     wake!(conn.write_waker)
        #     conn.write_waker = nothing
        # end
    end
end

main()
