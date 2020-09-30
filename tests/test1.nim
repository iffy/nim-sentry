import unittest
import os
import json
import sentry
import asyncdispatch

test "empty":
  let s = newSentryClient()
  s.init()
  check s.dsn == ""
  let exc = newException(CatchableError, "something")
  s.captureException(exc)
  try:
    raise newException(ValueError, "test")
  except:
    s.captureException()
  s.captureMessage("some message")

test "global":
  init("http://user@127.0.0.1:8080/1")
  captureMessage("from unit tests")
  waitFor flushSentry()

let dsn = getEnv("SENTRY_TEST_DSN")
if dsn != "":
  test "live":
    let s = newSentryClient()
    s.init(dsn)
    check s.dsn == dsn
    let exc = newException(CatchableError, "something")
    s.captureException(exc)
    try:
      raise newException(ValueError, "test")
    except:
      s.captureException()
    s.captureMessage("some message")
    waitFor s.flush()

when not defined(dryrun):
  echo "Pass -d:dryrun to run more tests"
else:
  test "environment":
    let s = newSentryClient()
    s.init("http://user@127.0.0.1:8000/1")
    s.scope["environment"] = %"test"
    s.captureMessage("foo")
    check s.sent[0].body["environment"].getStr() == "test"

  test "release":
    let s = newSentryClient()
    s.init("http://user@127.0.0.1:8000/1")
    s.scope["release"] = %"deadbeef"
    s.captureMessage("foo")
    check s.sent[0].body["release"].getStr() == "deadbeef"
  
  test "scope":
    let s = newSentryClient()
    s.init("http://user@127.0.0.1:8000/1")
    s.scope["foo"] = %"bar"
    let s2 = s.newScope()
    s2.scope["transaction"] = %"something"
    s2.captureMessage("foo")
    check s2.sent[0].body["transaction"].getStr() == "something"
    check s2.sent[0].body["foo"].getStr() == "bar"

    s.captureMessage("bar")
    check not s.sent[0].body.hasKey("transaction")
    check s.sent[0].body["foo"].getStr() == "bar"
