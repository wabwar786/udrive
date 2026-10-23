using System.Collections;
using System.Reflection;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace UDrive.Api.Security;

/// <summary>
/// Refuses any text that could carry HTML or script: <c>&lt;</c>, <c>&gt;</c>
/// and control characters (other than line breaks and tabs).
/// </summary>
/// <remarks>
/// Put on controllers whose input strangers or owners type and that other
/// people later see (hotels, vehicles, departures, the website, partner
/// requests). Every string in the request — route and query values, and every
/// string property of the body, nested lists included — is checked before the
/// action runs. The database has the same rule as a CHECK constraint
/// (migration 087), so a client that skips this API still cannot store it.
/// </remarks>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public sealed class RejectMarkupAttribute : ActionFilterAttribute
{
    private const int MaxDepth = 4;

    public override void OnActionExecuting(ActionExecutingContext context)
    {
        foreach (var value in context.ActionArguments.Values)
        {
            if (Find(value, 0) is { } field)
            {
                context.Result = new BadRequestObjectResult(new
                {
                    success = false,
                    error = "text_not_allowed",
                    message = $"Yeh nishan allowed nahi: < > (khana: {field}). Sirf saada text likhein.",
                });
                return;
            }
        }
    }

    internal static bool IsUnsafe(string? text)
    {
        if (string.IsNullOrEmpty(text)) return false;
        foreach (var ch in text)
        {
            if (ch is '<' or '>') return true;
            if (char.IsControl(ch) && ch is not ('\n' or '\r' or '\t')) return true;
        }
        return false;
    }

    /// <returns>The name of the first unsafe field, or null.</returns>
    private static string? Find(object? value, int depth)
    {
        switch (value)
        {
            case null:
                return null;
            case string s:
                return IsUnsafe(s) ? "text" : null;
            case IFormFile:
            case Stream:
                return null;
        }

        var type = value.GetType();
        if (type.IsPrimitive || type.IsEnum || value is decimal or DateTime or DateTimeOffset or DateOnly or TimeOnly or Guid)
        {
            return null;
        }

        if (depth >= MaxDepth) return null;

        if (value is IEnumerable list)
        {
            foreach (var item in list)
            {
                if (Find(item, depth + 1) is { } hit) return hit;
            }
            return null;
        }

        foreach (var property in type.GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (property.GetIndexParameters().Length > 0) continue;
            object? inner;
            try { inner = property.GetValue(value); }
            catch (TargetInvocationException) { continue; }

            if (inner is string s)
            {
                if (IsUnsafe(s)) return property.Name;
            }
            else if (Find(inner, depth + 1) is { } hit)
            {
                return hit == "text" ? property.Name : hit;
            }
        }

        return null;
    }
}
