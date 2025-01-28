import PostgresMigrations

extension DatabaseMigrations {
    public func addPackageRegistryMigrations() async {
        await self.add(CreatePackageRelease())
        await self.add(CreateURLPackageReference())
        await self.add(CreateManifest())
        await self.add(CreateUsers())
        await self.add(AddAdminUser())

    }
}
