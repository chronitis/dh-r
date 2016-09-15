# dh-r

## Debhelper for R packaging

`dh-r` provides a debhelper buildsystem for R packages. Using it should be as simple as replacing `cdbs` with `dh-r` in `Build-Depends` and replacing `debian/rules` with:

```
#!/usr/bin/make -f

%:
    dh $@ --buildsystem R
```

Optionally, you can request vignettes be built by adding `--with vignette`, but note that `r-base-dev` does not depend on a `LaTeX` installation, and you will need to explicitly add at least `texlive` and `texinfo` in addition to any R packages required.

### Features

`dh-r` should provide parity with the existing CDBS macro (`/usr/share/R/debian/r-cran.mk`) - choosing the correct library directory, setting the build timestamp from the changelog, generating `r-base-core` and `r-api-VERSION` dependencies and cleaning up some extraneous files.

In addition:

 * R packages already available in the archive are automatically detected and included in the `${R:Depends}`, `${R:Recommends}` and `${R:Suggests}` substvars
 * Script `dh-make-R` generates a `debian/` skeleton from an extracted R package tarball

### Notes

Build and install currently happens entirely during the debhelper `install` step (since `R CMD INSTALL` performs both as a single operation).

The `convert-to-dh-r` script reads an existing `debian/control` and outputs a new one to `stdout`, swapping `cdbs` for `dh-r` in `Build-Depends` and replacing binary package `Depends`, `Recommends` and `Suggests` with substvar versions. If there are depedencies apart from R and shlibs-detectable libraries they will need to be re-added.
