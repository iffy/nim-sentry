This is a Nim library that lets you log events with [Sentry](https://sentry.io).

# Installation

```
nimble install https://github.com/iffy/nim-sentry.git
```

# Usage

```nim
import sentry
init(dsn_that_you_get_from_sentry)
captureMessage("some message")
captureException(newException(ValueError, "Problem"))

import json
newScope(%* {"foo": "bar"}).captureMessage("another")
```
