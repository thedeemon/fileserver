use "http"
use "files"

actor Main
  """
  A simple HTTP server.
  """
  new create(env: Env) =>
    let service = try env.args(1)? else "3000" end
    let limit = try env.args(2)?.usize()? else 1000 end
    let host = "localhost"

    // let logger = CommonLog(env.out)
    // let logger = ContentsLog(env.out)
    let logger = DiscardLog

    let auth = try
      env.root as AmbientAuth
    else
      env.out.print("unable to use network")
      return
    end
    env.out.write("Listening at port ")
    env.out.print(service)

    // Start the top server control actor.
    HTTPServer(
      auth,
      ListenHandler(env),
      BackendMaker.create(env),
      logger
      where service=service, host=host, limit=limit, reversedns=auth)

class ListenHandler
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref listening(server: HTTPServer ref) =>
    try
      (let host, let service) = server.local_address().name()?
      _env.out.print("connected: " + host)
    else
      _env.out.print("Couldn't get local address.")
      server.dispose()
    end

  fun ref not_listening(server: HTTPServer ref) =>
    _env.out.print("Failed to listen.")

  fun ref closed(server: HTTPServer ref) =>
    _env.out.print("Shutdown.")

class BackendMaker is HandlerFactory
  let _env: Env

  new val create(env: Env) =>
    _env = env

  fun apply(session: HTTPSession): HTTPHandler^ =>
    BackendHandler.create(_env, session)

class BackendHandler is HTTPHandler
  """
  Notification class for a single HTTP session.  A session can process
  several requests, one at a time.  Data recieved using OneshotTransfer
  transfer mode is echoed in the response.
  """
  let _env: Env
  let _session: HTTPSession
  var _response: Payload = Payload.response()
  var fileOpt : (File | None) = None
  var _rspVal : Payload val = Payload.response()

  new ref create(env: Env, session: HTTPSession) =>
    _env = env
    _session = session

  fun ref apply(request: Payload val) =>
    _env.out.print(request.url.path)
    if request.url.path=="/" then
      _response.add_chunk("Hello, this is /")
    else
      try
        let fname = recover val request.url.path.substring(1) end
        let path = FilePath(_env.root as AmbientAuth, fname)?
        match OpenFile(path)
        | let f : File =>
          let sz = f.size()
          fileOpt = f
          _response.session = _session
          _response("Content-type") = mimeType(fname)
          _response.set_length(sz)
        else
          _response.add_chunk("File not found")
        end
      else
        _response.add_chunk("Error opening file")
      end
    end
    _rspVal = _response = Payload.response()
    _session(_rspVal)

  fun ref need_body() =>
    match fileOpt
    | let f : File =>
      while f.errno() is FileOK do
        _rspVal.send_chunk(f.read(32768))
      end
      _rspVal.finish()
    | None => None
    end

  fun endsWith(str: String, s: String): Bool =>
    let len = s.size()
    let ilen = ISize.from[USize](len)
    str.compare_sub(s, len, ISize.from[USize](str.size())-ilen, 0, true) is Equal

  fun mimeType(fname: String): String =>
    if endsWith(fname, ".html") or endsWith(fname, ".html") then
      "text/html"
    elseif endsWith(fname, ".txt") or endsWith(fname, ".json") then
      "text/plain"
    elseif endsWith(fname, ".js") then
      "application/javascript"
    else
      "application/octet-stream"
    end