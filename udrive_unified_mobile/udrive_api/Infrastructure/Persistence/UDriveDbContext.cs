using Microsoft.EntityFrameworkCore;
using UDrive.Api.Domain.Entities;

namespace UDrive.Api.Infrastructure.Persistence;

public sealed class UDriveDbContext(DbContextOptions<UDriveDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<CustomerProfile> CustomerProfiles => Set<CustomerProfile>();
    public DbSet<DriverProfile> DriverProfiles => Set<DriverProfile>();
    public DbSet<DriverDocument> DriverDocuments => Set<DriverDocument>();
    public DbSet<Vehicle> Vehicles => Set<Vehicle>();
    public DbSet<VehicleDocument> VehicleDocuments => Set<VehicleDocument>();
    public DbSet<TrustedContact> TrustedContacts => Set<TrustedContact>();
    public DbSet<Destination> Destinations => Set<Destination>();
    public DbSet<TourismRoute> Routes => Set<TourismRoute>();
    public DbSet<RouteAdvisory> RouteAdvisories => Set<RouteAdvisory>();
    public DbSet<TourInterest> TourInterests => Set<TourInterest>();
    public DbSet<TourPackage> TourPackages => Set<TourPackage>();
    public DbSet<PackageBooking> PackageBookings => Set<PackageBooking>();
    public DbSet<RideRequest> RideRequests => Set<RideRequest>();
    public DbSet<DriverOffer> DriverOffers => Set<DriverOffer>();
    public DbSet<Booking> Bookings => Set<Booking>();
    public DbSet<LiveLocation> LiveLocations => Set<LiveLocation>();
    public DbSet<SafetyIncident> SafetyIncidents => Set<SafetyIncident>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<Payment> Payments => Set<Payment>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasPostgresExtension("postgis");
        modelBuilder.HasDefaultSchema("udrive");

        ConfigureBase<User>(modelBuilder, "users");
        ConfigureBase<CustomerProfile>(modelBuilder, "customer_profiles");
        ConfigureBase<DriverProfile>(modelBuilder, "driver_profiles");
        ConfigureBase<DriverDocument>(modelBuilder, "driver_documents");
        ConfigureBase<Vehicle>(modelBuilder, "vehicles");
        ConfigureBase<VehicleDocument>(modelBuilder, "vehicle_documents");
        ConfigureBase<TrustedContact>(modelBuilder, "trusted_contacts");
        ConfigureBase<Destination>(modelBuilder, "destinations");
        ConfigureBase<TourismRoute>(modelBuilder, "routes");
        ConfigureBase<RouteAdvisory>(modelBuilder, "route_advisories");
        ConfigureBase<TourInterest>(modelBuilder, "tour_interests");
        ConfigureBase<TourPackage>(modelBuilder, "tour_packages");
        ConfigureBase<PackageBooking>(modelBuilder, "package_bookings");
        ConfigureBase<RideRequest>(modelBuilder, "ride_requests");
        ConfigureBase<DriverOffer>(modelBuilder, "driver_offers");
        ConfigureBase<Booking>(modelBuilder, "bookings");
        ConfigureBase<LiveLocation>(modelBuilder, "live_locations");
        ConfigureBase<SafetyIncident>(modelBuilder, "safety_incidents");
        ConfigureBase<Notification>(modelBuilder, "notifications");
        ConfigureBase<Payment>(modelBuilder, "payments");
        ConfigureBase<AuditLog>(modelBuilder, "audit_logs");

        modelBuilder.Entity<User>(entity =>
        {
            entity.HasIndex(x => x.PhoneNumber).IsUnique();
            entity.HasIndex(x => x.Email).IsUnique().HasFilter("email IS NOT NULL");
            entity.Property(x => x.Role).HasConversion<string>();
            entity.Property(x => x.Status).HasConversion<string>();
        });

        modelBuilder.Entity<DriverProfile>(entity =>
        {
            entity.Property(x => x.VerificationStatus).HasConversion<string>();
            entity.Property(x => x.Languages).HasColumnType("text[]");
            entity.Property(x => x.ServiceAreas).HasColumnType("text[]");
        });

        modelBuilder.Entity<DriverDocument>().Property(x => x.Status).HasConversion<string>();
        modelBuilder.Entity<Vehicle>().Property(x => x.Status).HasConversion<string>();
        modelBuilder.Entity<VehicleDocument>().Property(x => x.Status).HasConversion<string>();

        modelBuilder.Entity<Destination>(entity =>
        {
            entity.HasIndex(x => x.Slug).IsUnique();
            entity.Property(x => x.Location).HasColumnType("geography (point, 4326)");
            entity.HasIndex(x => x.Location).HasMethod("gist");
        });

        modelBuilder.Entity<TourismRoute>(entity =>
        {
            entity.Property(x => x.OriginLocation).HasColumnType("geography (point, 4326)");
            entity.Property(x => x.DestinationLocation).HasColumnType("geography (point, 4326)");
            entity.Property(x => x.RoutePath).HasColumnType("geography (linestring, 4326)");
            entity.HasIndex(x => x.OriginLocation).HasMethod("gist");
            entity.HasIndex(x => x.DestinationLocation).HasMethod("gist");
        });

        modelBuilder.Entity<RouteAdvisory>().Property(x => x.Severity).HasConversion<string>();
        modelBuilder.Entity<TourPackage>(entity =>
        {
            entity.Property(x => x.Status).HasConversion<string>();
            entity.Property(x => x.Inclusions).HasColumnType("text[]");
            entity.Property(x => x.Exclusions).HasColumnType("text[]");
            entity.Property(x => x.ItineraryJson).HasColumnType("jsonb");
        });

        modelBuilder.Entity<RideRequest>(entity =>
        {
            entity.Property(x => x.PickupLocation).HasColumnType("geography (point, 4326)");
            entity.Property(x => x.DestinationLocation).HasColumnType("geography (point, 4326)");
            entity.Property(x => x.BookingType).HasConversion<string>();
            entity.Property(x => x.Status).HasConversion<string>();
            entity.HasIndex(x => x.PickupLocation).HasMethod("gist");
        });

        modelBuilder.Entity<DriverOffer>().Property(x => x.Status).HasConversion<string>();
        modelBuilder.Entity<Booking>(entity =>
        {
            entity.Property(x => x.BookingType).HasConversion<string>();
            entity.Property(x => x.Status).HasConversion<string>();
        });
        modelBuilder.Entity<PackageBooking>(entity =>
        {
            entity.Property(x => x.BookingType).HasConversion<string>();
            entity.Property(x => x.Status).HasConversion<string>();
        });
        modelBuilder.Entity<LiveLocation>(entity =>
        {
            entity.Property(x => x.Location).HasColumnType("geography (point, 4326)");
            entity.HasIndex(x => x.Location).HasMethod("gist");
            entity.HasIndex(x => new { x.BookingId, x.RecordedAt });
        });
        modelBuilder.Entity<SafetyIncident>().Property(x => x.Severity).HasConversion<string>();
        modelBuilder.Entity<Payment>().Property(x => x.Status).HasConversion<string>();
        modelBuilder.Entity<Notification>().Property(x => x.DataJson).HasColumnType("jsonb");
        modelBuilder.Entity<AuditLog>().Property(x => x.ChangesJson).HasColumnType("jsonb");
    }

    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var entry in ChangeTracker.Entries<BaseEntity>())
        {
            if (entry.State == EntityState.Added)
            {
                entry.Entity.CreatedAt = now;
            }

            if (entry.State is EntityState.Added or EntityState.Modified)
            {
                entry.Entity.UpdatedAt = now;
            }
        }

        return base.SaveChangesAsync(cancellationToken);
    }

    private static void ConfigureBase<TEntity>(ModelBuilder modelBuilder, string tableName)
        where TEntity : BaseEntity
    {
        modelBuilder.Entity<TEntity>(entity =>
        {
            entity.ToTable(tableName);
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.CreatedAt).HasColumnName("created_at");
            entity.Property(x => x.UpdatedAt).HasColumnName("updated_at");
        });
    }
}
