
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

Deploy the stack like this:

    $> awsboxen deploy oldsync-dev-lcip-org

