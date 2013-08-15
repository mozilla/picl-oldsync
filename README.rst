
PiCL Dev Deployment Scripts for Old Sync
========================================

This is a set of deployment scripts for a simple dev deplopment of
"Old Sync", the current and soon-to-be-outdated storage service behind
Firefox Sync.

It's designed to give us some machine to test against while we flesh out
Firefox Accounts; don't use it for anythig serious!

You'll need awsboxen to make this work:

    https://github.com/mozilla/awsboxen

Deploy the stack like this:

    $> awsboxen deploy oldsync-dev-lcip-org

