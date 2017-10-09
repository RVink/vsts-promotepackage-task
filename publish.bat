rm *.vsix
tfx extension create -manifest-globs vss-extension.json --rev-version && tfx extension publish --service-url http://tfs/tfs
