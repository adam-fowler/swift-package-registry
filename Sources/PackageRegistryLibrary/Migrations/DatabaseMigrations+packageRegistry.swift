import PostgresMigrations

extension DatabaseMigrations {
    public func addPackageRegistryMigrations() async {
        self.add(CreatePackageRelease())
        self.add(CreateURLPackageReference())
        self.add(CreateManifest())
        self.add(CreateUsers())
        self.add(AddAdminUser())
    }
}
