using Hyper
using Sockets
using StringViews
using FileWatching

include("utils.jl")

struct UploadBody
    io::IOStream
    max_len::Int
end

function poll_req_upload(upload, ctx::Context, buf_ref::Ref{Union{Buf,Nothing}})
    try
        res = read(upload.io, upload.max_len)
        buf_ref[] = isempty(res) ? nothing : Buf(res)
        return HYPER_POLL_READY
    catch e
        @error e
        return HYPOER_POLL_ERROR
    end
end

function print_informational(userdata, resp::Response)
    println("\nInformational (1xx): $(resp.status)")

    println(resp.raw_headers)
end

function main()
    file = length(ARGS) > 0 ? ARGS[1] : ""
    host = length(ARGS) > 1 ? ARGS[2] : "httpbin.org"
    port = length(ARGS) > 2 ? parse(Int, ARGS[3]) : 80
    path = length(ARGS) > 3 ? ARGS[4] : "/post"

    if !isfile(file)
        @error "You need to specify a file to upload"
        return
    end

    ios = open(file, "r")
    upload = UploadBody(ios, 8192)

    println("connecting to port $port on $host...")

    socket = connect(host, port)
    rawfd = getrawfd(socket)
    conn = ConnData(rawfd, socket, nothing, nothing)
    io = HyperIO()
    io.userdata = conn
    io.read = read_cb!
    io.write = write_cb!

    println("connected to $host, now upload to $path...")

    println("http handshake (hyper v$(Hyper.version())) ...")

    executor = Executor()
    opts = ClientconnOptions()
    exec(opts, executor)

    hs = handshake!(io, opts)
    hs.userdata = EXAMPLE_HANDSHAKE
    push!(executor, hs)

    resp_body = Body()

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
                req.method = "POST"
                req.uri = path

                headers = req.headers
                headers.host = host
                headers.expect = "100-continue"

                println("    with expect-continue ...")
                on_informational!(req, print_informational)

                body = Body()
                body.userdata = upload
                body.datafunc = poll_req_upload
                req.body = body

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

                resp_body = resp.body
                data_task = poll(resp_body)
                data_task.userdata = EXAMPLE_RESP_BODY
                push!(executor, data_task)
                Hyper.free!(resp)

                break
            elseif task_type == EXAMPLE_RESP_BODY
                if task.type == Hyper.TASK_ERROR
                    @error task.value
                    return
                elseif task.type == Hyper.TASK_BUF
                    chunk = task.value
                    println(chunk)
                    Hyper.free!(chunk)
                    Hyper.free!(task)

                    data_task = poll(resp_body)
                    data_task.userdata = EXAMPLE_RESP_BODY
                    push!(executor, data_task)

                    break
                else
                    @assert task.type == Hyper.TASK_EMPTY
                    println(" -- Done! -- ")

                    Hyper.free!(task)
                    Hyper.free!(resp_body)
                    Hyper.free!(executor)
                    free!(conn)

                    return 0
                end
            elseif task_type == EXAMPLE_NOT_SET
                Hyper.free!(task)
                break
            else
                @error "Unknown task type"
                return
            end
        end

        result = poll_fd(handle(conn.fd); readable=true, writable=true)

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
