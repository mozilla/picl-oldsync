
PiCL Dev Deployment Scripts for Old Sync
========================================

This is a set of deployment scripts for a simple dev deplopment of "Old
Sync", a hacked-up combination of the tokenserver and server-storage projects
the will serve as an initial proving-ground for the next generation of
Firefox Sync.

It's designed to give us some machine to test against while we flesh out
Firefox Accounts; don't use it for anything serious!

You'll need awsboxen to make this work:

    https://github.com/mozilla/awsboxen

Clone this repo and `cd` into it, then deploy the stack like this:

    $> awsboxen deploy oldsync-dev-lcip-org

It will deploy two servers.  The first is the "auth" server available at:

    http://auth.oldsync.dev.lcip.org

This is running the "tokenserver" codebase, which is responsible for accepting
BrowserID identity assertions and exchanging them for short-lived access
credentials:

    https://github.com/mozilla-services/tokenserver
    http://docs.services.mozilla.com/token/index.html

The second is the "storage" server available at:

    http://db1.oldsync.dev.lcip.org

This is running the "server-storage" codebase, the storage engine that powers
the existing Firefox Sync service.  It uses a plugin to let users authenticate
via Hawk using the tokenserver-provided credentials, rather than the usual
username and password:

    http://hg.mozilla.org/services/server-storage
    http://docs.services.mozilla.com/storage/index.html
    https://github.com/mozilla-services/repoze.who.plugins.hawkauth
    https://github.com/mozilla-services/hawkauthlib

