# SQL Administrator

SQL Administrator is a single file SQL administrator tool built using ASP.NET Web Forms.

The tool is meant to be used in situations where you cannot connect to SQL Server from the outside, usually due to (very reasonable) firewall restrictions.

Below is a screen shot of SQL Administrator connected to an instance of the Northwind database.

![screenshot](screenshot.jpg "SQL Administrator connected to the Northwind database")

## Instructions

Edit `SqlAdministrator.aspx` line 12 to reference the named connection string you want to use.

```csharp
private readonly string _connectionString = WebConfigurationManager.ConnectionStrings["ConnectionString"].ConnectionString;
```

Edit your `Web.config` file to secure the `SqlAdministrator.aspx` file:

```xml
<location path="SqlAdministrator.aspx">
  <system.web>
    <authorization>
      <deny users="?"/>
    </authorization>
  </system.web>
</location>
```

Drop the `SqlAdministrator.aspx` in the root of your web app.

You can now browse to `~/SqlAdministrator.aspx` to start working with your online database.
