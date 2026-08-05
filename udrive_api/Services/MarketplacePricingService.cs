using Npgsql;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class MarketplacePricingService(string connectionString)
{
    public async Task<IReadOnlyList<ServiceVehicleRateDto>> GetRatesAsync(string serviceType,CancellationToken ct)
    {
        const string sql="select service_type,vehicle_category,per_seat_rate,whole_vehicle_rate,currency from udrive.service_vehicle_rates where is_active=true and lower(service_type)=lower(@service) order by vehicle_category";
        var list=new List<ServiceVehicleRateDto>();
        await using var cn=new NpgsqlConnection(connectionString);await cn.OpenAsync(ct);
        await using var cmd=new NpgsqlCommand(sql,cn);cmd.Parameters.AddWithValue("service",serviceType);
        await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new(r.GetString(0),r.GetString(1),r.GetDecimal(2),r.GetDecimal(3),r.GetString(4)));
        return list;
    }

    public async Task<bool> UpdatePresenceAsync(Guid userId,DriverPresenceUpdateRequest request,CancellationToken ct)
    {
        const string sql=@"insert into udrive.driver_presence_locations(driver_profile_id,location,accuracy_meters,device_timestamp,server_timestamp,updated_at)
select dp.id,ST_SetSRID(ST_MakePoint(@lng,@lat),4326)::geography,@accuracy,@device,now(),now() from udrive.driver_profiles dp
where dp.user_id=@user and dp.verification_status='Approved'
on conflict(driver_profile_id) do update set location=excluded.location,accuracy_meters=excluded.accuracy_meters,device_timestamp=excluded.device_timestamp,server_timestamp=now(),updated_at=now()";
        await using var cn=new NpgsqlConnection(connectionString);await cn.OpenAsync(ct);await using var cmd=new NpgsqlCommand(sql,cn);
        cmd.Parameters.AddWithValue("user",userId);cmd.Parameters.AddWithValue("lng",request.Longitude);cmd.Parameters.AddWithValue("lat",request.Latitude);cmd.Parameters.AddWithValue("accuracy",(object?)request.Accuracy??DBNull.Value);cmd.Parameters.AddWithValue("device",request.DeviceTimestamp.ToUniversalTime());
        return await cmd.ExecuteNonQueryAsync(ct)>0;
    }
}
