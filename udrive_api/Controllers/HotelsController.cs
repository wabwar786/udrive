using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController,Route("api/v1/hotels")]
public sealed class HotelsController(HotelService service):ControllerBase
{
    // GetUserIdOrNull, not GetRequiredUserId: this endpoint is anonymous and
    // stays anonymous. The id is passed only so the self-test harness's own
    // hotel can be shown to the self-test customer and hidden from everyone
    // else — see the guard clause in HotelService.SearchAsync.
    [AllowAnonymous,HttpGet] public async Task<IActionResult> Search([FromQuery]string? query,[FromQuery]string? city,[FromQuery]DateOnly? checkIn,[FromQuery]DateOnly? checkOut,[FromQuery]int guests=1,[FromQuery]int rooms=1,[FromQuery]int page=1,[FromQuery]int pageSize=20,CancellationToken ct=default)=>Result(await service.SearchAsync(new(query,city,checkIn,checkOut,guests,rooms,page,pageSize),User.GetUserIdOrNull(),ct));
    [AllowAnonymous,HttpGet("{id:guid}")] public async Task<IActionResult> Get(Guid id,[FromQuery]DateOnly? checkIn,[FromQuery]DateOnly? checkOut,CancellationToken ct)=>Result(await service.GetAsync(id,checkIn,checkOut,ct));
    [Authorize,HttpGet("owner/my")] public async Task<IActionResult> Mine(CancellationToken ct)=>Result(await service.MyHotelsAsync(User.GetRequiredUserId(),ct));
    [Authorize,HttpPost("owner")] public async Task<IActionResult> Create(CreateHotelRequest x,CancellationToken ct)=>Result(await service.CreateAsync(User.GetRequiredUserId(),x,ct));
    [Authorize,HttpGet("owner/bookings")] public async Task<IActionResult> OwnerBookings([FromQuery]Guid? hotelId,CancellationToken ct)=>Result(await service.OwnerBookingsAsync(User.GetRequiredUserId(),hotelId,ct));
        [Authorize,HttpPost("owner/{hotelId:guid}/rooms")] public async Task<IActionResult> AddRoom(Guid hotelId,CreateHotelRoomRequest x,CancellationToken ct)=>Result(await service.AddRoomAsync(User.GetRequiredUserId(),hotelId,x,ct));
    [Authorize,HttpGet("my-bookings")] public async Task<IActionResult> MyBookings(CancellationToken ct)=>Result(await service.MyBookingsAsync(User.GetRequiredUserId(),ct));

    /// <summary>
    /// Books the room, then tells the hotel on WhatsApp who is coming and when.
    /// </summary>
    /// <remarks>
    /// The message goes after the booking is committed and never undoes it: a
    /// guest with a confirmed room must not be turned away because WhatsApp was
    /// slow. Whether it went out is recorded on the booking and returned as
    /// <c>ownerNotified</c>, so the app can tell the customer to call instead.
    /// </remarks>
    [Authorize,HttpPost("{hotelId:guid}/bookings")]
    public async Task<IActionResult> Book(Guid hotelId,CreateHotelBookingRequest x,[FromServices]WhatsAppService whatsApp,[FromServices]ILogger<HotelsController> logger,CancellationToken ct)
    {
        var result=await service.BookAsync(User.GetRequiredUserId(),hotelId,x,ct);
        if(!result.Success||result.Data is null)return Result(result);

        var booking=result.Data;
        var notified=false;
        try
        {
            var notice=await service.OwnerNoticeAsync(booking.BookingId,CancellationToken.None);
            if(notice is not null)
            {
                using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(12));
                var sent=await whatsApp.SendTextAsync(notice.To,notice.Message,timeout.Token);
                notified=sent.Success;
                await service.RecordOwnerNoticeAsync(booking.BookingId,sent.Success,sent.Success?null:sent.ErrorCode,CancellationToken.None);
            }
        }
        catch(Exception exception)
        {
            logger.LogError(exception,"Hotel booking {BookingId} was saved but the owner could not be messaged.",booking.BookingId);
        }
        return Ok(new{success=true,data=booking with{OwnerNotified=notified}});
    }
    [Authorize(Roles="Admin,SuperAdmin"),HttpGet("admin")] public async Task<IActionResult> AdminList([FromQuery]string? status,[FromQuery]string? query,CancellationToken ct)=>Result(await service.AdminListAsync(status,query,ct));
    [Authorize(Roles="Admin,SuperAdmin"),HttpGet("admin/pending")] public async Task<IActionResult> Pending(CancellationToken ct)=>Result(await service.PendingAsync(ct));
    [Authorize(Roles="Admin,SuperAdmin"),HttpPost("admin/{id:guid}/review")] public async Task<IActionResult> Review(Guid id,ReviewHotelRequest x,CancellationToken ct)=>Result(await service.ReviewAsync(User.GetRequiredUserId(),id,x,ct));
    [Authorize(Roles="Admin,SuperAdmin"),HttpPatch("admin/{id:guid}/active")] public async Task<IActionResult> SetActive(Guid id,SetHotelActiveRequest x,CancellationToken ct)=>Result(await service.SetActiveAsync(User.GetRequiredUserId(),id,x.IsActive,ct));
    IActionResult Result<T>(ServiceResult<T> r)=>r.Success?Ok(new{success=true,data=r.Data}):StatusCode(r.StatusCode,new{success=false,error=r.ErrorCode,message=r.Message});
}
