# lotro-compendium-tools




## update Submodules

```
-- init one time
git submodule update --init --recursive

git submodule update --recursive

# git pull origin master --recurse-submodules
```

```
# update periodically to have latest
git submodule foreach git pull origin master
```
