# Module-Packaged-Report Perl module

## Release process

* Update VERSION in module
* Update the Changes file

    perl Build.PL
    perl Build
    perl Build test
    perl Build manifest
    perl Build dist

## Issues

For the testing we would need several modules

Module::Packaged and Parse::Fedora::Packages both fail their own tests.
We can install them using `cpanm --notest`, but at least on of the tests
of Module-Packaged-Report also fails.
