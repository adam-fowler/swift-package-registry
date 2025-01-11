# Swift Package Registry

This is an implementation of a Swift Package Registry as detailed [here](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md).

## Package Registry Setup

Before running you will need to create a server key pair to support https access. You can then provide these as environment variables `server_certificate_chain` and `server_private_key`. It is easiest to add a `.env` file of the form

```
server_private_key="
-----BEGIN PRIVATE KEY-----
MII...
-----END PRIVATE KEY-----
"
server_certificate_chain="
-----BEGIN CERTIFICATE-----
MII...
-----END CERTIFICATE-----
"
```

### Database setup

You can run the server just using in memory storage with commandline `--in-memory`. But everytime you stop the server you will lose all your data. It is preferable to use a postgres database for data storage. There is a docker-compose file included with the project that'll bring up a postgres database, with the correct database and login details.

The first time you run the project you should run it with the `--migrate` commandline to do the database migration. One of the migration steps includes adding an `admin` user and the password for this user will be posted to the logs. Keep a record of this.

## Swift Package Manager setup

Before using the registry you need to tell the swift package manager about it. If running locally with https you can use the following to do this

```sh
swift package-registry set https://localhost:8080/registry
```

If you want to publish packages to the registry you need to setup login details. Using the admin password setup during the migration you can login as follows

```sh
swift package-registry login https://localhost:8080/registry --username admin --password <password>
```

## Publishing packages

The project comes with a small helper script for publishing GitHUb stored packages to the registry. It requires you have `jq` and `gh` (the GitHub commandline tool) installed. To publish the latest version of a package run

```sh
./scripts/publish.sh <org>/<package>
```

To publish a specific version of a package you can include the version as a second parameter eg to publish version 1.0.0 of swift-log from Apple you can do the following. 

```sh
./scripts/publish.sh apple/swift-log 1.0.0
```

## Using packages from registry

The easiest way to use a registry is to add the commandline option `--replace-scm-with-registry` to your `swift package resolve` or `swift package upload` calls.

Read [PackageRegistryUsage.md](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) to find out more about using swift package registries.

## Using HTTP instead

If you don't set the server certificate chain and private key environment variables up it will run the server using `http` rather than `https`. You can run most swift package registry functions with a `--allow-insecure-http` command line parameter. 

Unfortunately the login command doesnt have this option so admin user authentication is disabled if you run the server using only http.

