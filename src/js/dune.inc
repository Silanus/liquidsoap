
(rule
 (target filesystem.js)
 (deps
  (:stdlib_js ./stdlib_js.liq)
  (source_tree ../libs))
 (action
  (run js_of_ocaml build-fs -I . -I ../libs -o %{target} %{stdlib_js} visualization.liq
resolvers.liq
externals.liq
gstreamer.liq
log.liq
utils.liq
thread.liq
source.liq
process.liq
ref.liq
fades.liq
profiler.liq
null.liq
math.liq
error.liq
request.liq
string.liq
stdlib.liq
deprecations.liq
liquidsoap.liq
audio.liq
clock.liq
protocols.liq
video.liq
ffmpeg.liq
native.liq
interactive.liq
http_codes.liq
predicate.liq
file.liq
shoutcast.liq
getter.liq
io.liq
switches.liq
list.liq
telnet.liq
http.liq
metadata.liq
lastfm.liq
playlist.liq
hls.liq
runtime.liq
json.liq
server.liq
settings.liq)))
  