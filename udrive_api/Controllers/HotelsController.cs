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
    [AllowAnonymous,HttpGet] public async Task<IActionResult> Search([FromQuery]string? query,[FromQuery]string? city,[FromQuery]DateOnly? checkIn,[FromQuery]DateOnly? checkOut,[FromQuery]int guests=1,[FromQuery]int rooms=1,[FromQuery]int page=1,[FromQuery]int pageSize=20,CancellationToken ct=default)=>Result(await service.SearchAsync(new(query,city,checkIn,checkOut,guests,rooms,page,pageSize),ct));
    [AllowAnonymous,HttpGet("{id:guid}")] public async Task<IActionResult> Get(Guid id,[FromQuery]DateOnly? checkIn,[FromQuery]DateOnly? checkOut,CancellationToken ct)=>Result(await service.GetAsync(id,checkIn,checkOut,ct));
    [Authorize,HttpGet("owner/my")] public async Task<IActionResult> Mine(CancellationToken ct)=>Result(await service.MyHotelsAsync(User.GetRequiredUserId(),ct));
    [Authorize,HttpPost("owner")] public async Task<IActionResult> Create(CreateHotelRequest x,CancellationToken ct)=>Result(await service.CreateAsync(User.GetRequiredUserId(),x,ct));
    [Authorize,HttpGet("owner/bookings")] public async Task<IActionResult> OwnerBookings([FromQuery]Guid? hotelId,CancellationToken ct)=>Result(await service.OwnerBookingsAsync(User.GetRequiredUserId(),hotelId,ct));
        [Authorize,HttpPost("owner/{hotelId:guid}/rooms")] public async Task<IActionResult> AddRoom(Guid hotelId,CreateHotelRoomRequest x,CancellationToken ct)=>Result(await service.AddRoomAsync(User.GetRequiredUserId(),hotelId,x,ct));
    [Authorize,HttpPost("{hotelId:guid}/bookings")] public async Task<IActionResult> Book(Guid hotelId,CreateHotelBookingRequest x,CancellationToken ct)=>Result(await service.BookAsync(User.GetRequiredUserId(),hotelId,x,ct));
    [Authorize(Roles="Admin,SuperAdmin"),HttpGet("admin/pending")] public async Task<IActionResult> Pending(CancellationToken ct)=>Result(await service.PendingAsync(ct));
    [Authorize(Roles="Admin,SuperAdmin"),HttpPost("admin/{id:guid}/review")] public async Task<IActionResult> Review(Guid id,ReviewHotelRequest x,CancellationToken ct)=>Result(await service.ReviewAsync(User.GetRequiredUserId(),id,x,ct));
    IActionResult Result<T>(ServiceResult<T> r)=>r.Success?Ok(new{success=true,data=r.Data}):StatusCode(r.StatusCode,new{success=false,error=r.ErrorCode,message=r.Message});
}
