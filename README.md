This is a repository for building libsodium so that I don't have to rebuild repeatedly in other places.

# Get static libsodium now

```
curl -sL 'https://raw.githubusercontent.com/iffy/libsodium-builds/refs/heads/master/install_libsodium_static.sh' | bash
```


# Development of this repo

To make a new build:

1. Push a branch to GitHub
2. See if it succeeds
3. If it does, merge that into the `master` branch
4. Push `master` branch to GitHub and a release will automatically be created
