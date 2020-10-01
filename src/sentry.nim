import asyncdispatch
import httpclient
import json
import options
import strformat
import strutils
import times
import uri
import uuids
import logging

const CLIENT_VERSION = "0.1.0"

when defined(dryrun):
  type
    LoggedRequest* = tuple
      url: string
      body: JsonNode
      headers: HttpHeaders

type
  SentryClient* = ref object of RootObj
    dsn*: string
    baseurl: string
    public_key: string
    secret_key: string
    scope*: JsonNode
    when defined(dryrun):
      sent*: seq[LoggedRequest]

template neverFail(body: untyped): untyped =
  try:
    body
  except:
    warn "[sentry] failure in sentry code: " & getCurrentExceptionMsg()

proc newSentryClient*(): SentryClient =
  new(result)
  result.scope = %* {
    "platform": "other"
  }

proc tstamp(): string {.inline.} =
  getTime().format("yyyy-MM-dd\'T\'HH:mm:ss\'Z\'", utc())

proc copyAndMerge(base: JsonNode, newdata: JsonNode): JsonNode =
  ## Merge 2 JObjects, leaving old objects unchanged
  result = base.copy()
  for k,v in newdata.pairs:
    result[k] = v

proc merge(base: JsonNode, newdata: JsonNode): JsonNode =
  ## Merge 2 JObjects, mutating the base object and returning it.
  result = base
  for k,v in newdata.pairs:
    result[k] = v

proc init*(s: SentryClient, dsn = "") =
  neverFail:
    s.dsn = dsn
    if dsn == "":
      warn "[sentry] init without DSN"
    else:
      let parsed = parseUri(dsn)
      let parts = parsed.path.rsplit("/", 1)
      let path = parts[0]
      let project_id = parts[1]
      s.baseurl = &"{parsed.scheme}://{parsed.hostname}{path}/api/{project_id}"
      s.public_key = parsed.username
      s.secret_key = parsed.password

proc auth_header(s: SentryClient): string =
  result = &"Sentry sentry_version=7, sentry_client=nim-sentry/{CLIENT_VERSION}, sentry_timestamp={getTime().toUnixFloat()}, sentry_key={s.public_key}"
  if s.secret_key != "":
    result.add(&", sentry_secret={s.secret_key}")

proc uuid(): string {.inline.} = ($genUUID()).replace("-", "")

proc sendEvent(s: SentryClient, data: JsonNode) =
  neverFail:
    if s.baseurl == "":
      warn "[sentry] unconfigured attempt to send event"
    else:
      var ev = s.scope.copyAndMerge(%* {
        "event_id": uuid(),
        "timestamp": tstamp(),
      }).merge(data)
      let url = s.baseurl & "/store/"
      let client = newAsyncHttpClient()
      client.headers = newHttpHeaders({
        "X-Sentry-Auth": s.auth_header(),
        "Content-Type": "application/json",
        "User-Agent": "nim-sentry/" & CLIENT_VERSION,
      })
      when defined(dryrun):
        let req: LoggedRequest = (url, ev, client.headers)
        s.sent.add(req)
      else:
        asyncCheck client.postContent(url, body = $ev)

proc captureException*(s: SentryClient, exc: ref Exception) =
  neverFail:
    if s.baseurl == "":
      warn "[sentry] unconfigured attempt to captureException"
    else:
      var chain = newJArray()
      var pexc = exc
      while not pexc.isNil:
        chain.add(%* {
          "type": $pexc.name,
          "value": $pexc.msg,
        })
        pexc = pexc.parent
      s.sendEvent(%* {
        "exception": {
          "values": chain,
        }
      })

proc captureException*(s: SentryClient) {.inline.} =
  neverFail:
    s.captureException(getCurrentException())

proc captureMessage*(s: SentryClient, msg: string) =
  neverFail:
    if s.baseurl == "":
      warn "[sentry] unconfigured attempt to captureMessage"
    else:
      s.sendEvent(%* {
        "level": "info",
        "message": {
          "formatted": msg,
        }
      })

proc newScope*(s: SentryClient, data = newJNull()): SentryClient =
  result = newSentryClient()
  result.init(s.dsn)
  result.scope = s.scope.copy()
  if data.kind == JObject:
    result.scope = result.scope.merge(data)

proc flush*(s: SentryClient): Future[void] {.async.} =
  neverFail:
    if s.baseurl != "":
      try:
        drain()
      except ValueError:
        discard

#-----------------------------------------------------------------
# Global instance
#-----------------------------------------------------------------
var sentryClient* = newSentryClient()

proc init*(dsn = "") {.inline.} =
  sentryClient.init(dsn)

proc captureException*(exc: ref Exception) {.inline.} =
  sentryClient.captureException(exc)

proc captureException*() {.inline.} =
  sentryClient.captureException()

proc captureMessage*(msg: string) {.inline.} =
  sentryClient.captureMessage(msg)

proc newScope*(data = newJNull()): SentryClient =
  sentryClient.newScope(data)

proc flushSentry*(): Future[void] {.inline.} =
  sentryClient.flush()
