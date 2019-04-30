<%@ Page Language="C#" AutoEventWireup="true" Culture="en-GB" UICulture="en-GB" %>

<%@ Import Namespace="System.Collections.Generic" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Linq" %>
<%@ Import Namespace="System.Web.Configuration" %>

<!DOCTYPE html>

<script runat="server">
    private readonly string _connectionString = WebConfigurationManager.ConnectionStrings["ConnectionString"].ConnectionString;

    private void Page_Load(object sender, EventArgs e)
    {
        if (!IsPostBack)
        {
            try
            {
                using (var connection = new SqlConnection(_connectionString))
                {
                    connection.Open();
                }
            }
            catch (Exception ex)
            {
                ErrorLabel.Text = ex.Message;
            }
        }
    }

    private void Execute_Click(object sender, EventArgs e)
    {
        ErrorLabel.Text = null;
        ReturnLabel.Text = null;
        Results.Controls.Clear();

        if (string.IsNullOrWhiteSpace(Query.Text))
        {
            ErrorLabel.Text = "Query cannot be blank";
            return;
        }

        DataSet set;
        try
        {
            int result;
            set = SqlQuery(Query.Text, out result);
            ReturnLabel.Text = string.Format("({0} row(s) affected)", result);
        }
        catch (SqlException ex)
        {
            ErrorLabel.Text = ex.Message;
            return;
        }

        foreach (var table in set.Tables)
        {
            var grid = new GridView { DataSource = table };
            Results.Controls.Add(grid);
            grid.DataBind();
        }
    }

    private void Reset_Click(object sender, EventArgs e)
    {
        Query.Text = null;
        ErrorLabel.Text = null;
        ReturnLabel.Text = null;
        Results.Controls.Clear();
    }

    private void Tree_TreeNodePopulate(object sender, TreeNodeEventArgs e)
    {
        switch (e.Node.Value)
        {
            case "TABLE":
                LoadNodes(e.Node, Tables(), true);
                return;
            case "VIEW":
                LoadNodes(e.Node, Views(), true);
                return;
            case "SPROC":
                LoadNodes(e.Node, StoredProcedures(), true);
                return;
        }

        if (!e.Node.Value.Contains("."))
        {
            return;
        }

        var type = e.Node.Value.Substring(0, e.Node.Value.IndexOf("."));
        var id = e.Node.Value.Substring(e.Node.Value.IndexOf(".") + 1);

        switch (type)
        {
            case "TABLE":
            case "VIEW":
                LoadNodes(e.Node, Columns(id), false);
                return;
            case "SPROC":
                LoadNodes(e.Node, Parameters(id), false);
                return;
        }
    }

    private void LoadNodes(TreeNode root, IEnumerable<KeyValuePair<string, string>> entities, bool hasChildren)
    {
        root.ChildNodes.Clear();

        foreach (var entity in entities)
        {
            var node = new TreeNode
            {
                Text = entity.Value,
                Value = entity.Key,
                PopulateOnDemand = hasChildren,
                SelectAction = hasChildren ? TreeNodeSelectAction.Select : TreeNodeSelectAction.None
            };
            root.ChildNodes.Add(node);
        }
    }

    private void Tree_SelectedNodeChanged(object sender, EventArgs e)
    {
        var node = Tree.SelectedNode;

        if (!node.Value.Contains("."))
        {
            return;
        }

        var type = node.Value.Substring(0, node.Value.IndexOf("."));
        var id = node.Value.Substring(node.Value.IndexOf(".") + 1);

        switch (type)
        {
            case "TABLE":
                var select = Select(id);
                Query.Text = select;
                return;
            case "VIEW":
            case "SPROC":
                var definition = GetDefinition(id);
                Query.Text = definition.Value;
                return;
        }
    }

    private void Refresh_Click(object sender, EventArgs e)
    {
        Tree.Nodes.Clear();
        Tree.Nodes.Add(new TreeNode("Tables", "TABLE") { PopulateOnDemand = true, SelectAction = TreeNodeSelectAction.None, Expanded = false });
        Tree.Nodes.Add(new TreeNode("Views", "VIEW") { PopulateOnDemand = true, SelectAction = TreeNodeSelectAction.None, Expanded = false });
        Tree.Nodes.Add(new TreeNode("Stored Procedures", "SPROC") { PopulateOnDemand = true, SelectAction = TreeNodeSelectAction.None, Expanded = false });
    }

    private IEnumerable<KeyValuePair<string, string>> Tables()
    {
        const string query = @"SELECT 
                'TABLE' + '.' + SCHEMA_NAME(schema_id) + '.' + name AS Id
               ,SCHEMA_NAME(schema_id) + '.' + name AS Name
            FROM 
                sys.tables
            ORDER BY
                SCHEMA_NAME(schema_id)
               ,name";

        return LoadData(query);
    }

    private IEnumerable<KeyValuePair<string, string>> Views()
    {
        const string query = @"SELECT 
                'VIEW' + '.' + SCHEMA_NAME(schema_id) + '.' + name AS Id
               ,SCHEMA_NAME(schema_id) + '.' + name AS Name
            FROM 
                sys.views
            ORDER BY
                SCHEMA_NAME(schema_id)
               ,name";

        return LoadData(query);
    }

    private IEnumerable<KeyValuePair<string, string>> StoredProcedures()
    {
        const string query = @"SELECT 
                'SPROC' + '.' + SCHEMA_NAME(schema_id) + '.' + name AS Id
               ,SCHEMA_NAME(schema_id) + '.' + name AS Name
            FROM 
                sys.procedures
            ORDER BY
                SCHEMA_NAME(schema_id)
               ,name";

        return LoadData(query);
    }

    private string Select(string tableOrView)
    {
        const string query = @"SELECT 
                QUOTENAME(c.Name) AS Id
               ,QUOTENAME(c.Name) AS Name
            FROM  
                sys.columns AS c
                JOIN sys.types AS t ON c.system_type_id = t.system_type_id AND c.user_type_id = t.user_type_id
            WHERE
                c.object_id = OBJECT_ID(@TableOrView)
            ORDER BY
                column_id";

        var parameter = new SqlParameter("@TableOrView", tableOrView);

        var columns = LoadData(query, parameter);

        var select = new StringBuilder();
        select.AppendLine("SELECT TOP 1000");
        select.AppendLine("    " + string.Join("\r\n   ,", columns.Select(c => c.Key)));
        select.AppendLine("FROM\r\n    " + tableOrView);

        return select.ToString();
    }

    private IEnumerable<KeyValuePair<string, string>> Columns(string tableOrView)
    {
        const string query = @"SELECT 
                'COLUMN' + '.' + @TableOrView + '.' + c.name AS Id
               ,c.name + ' (' + t.name + CASE WHEN t.name IN ('time', 'datetime2', 'datetimeoffset', 'varbinary', 'varchar', 'binary', 'char', 'nvarchar', 'nchar') THEN '(' + CASE WHEN c.max_length = -1 THEN 'max' ELSE CAST(c.max_length AS nvarchar(50)) END + ')' ELSE '' END + ')' AS Name
            FROM  
                sys.columns AS c
                JOIN sys.types AS t ON c.system_type_id = t.system_type_id AND c.user_type_id = t.user_type_id
            WHERE
                object_id = OBJECT_ID(@TableOrView)
            ORDER BY
                column_id";

        var parameter = new SqlParameter("@TableOrView", tableOrView);

        return LoadData(query, parameter);
    }

    private IEnumerable<KeyValuePair<string, string>> Parameters(string storedProcedure)
    {
        const string query = @"SELECT 
                'PARAMETER' + '.' + @StoredProcedure + '.' + p.name AS Id
               ,p.name + ' (' + t.name + CASE WHEN t.name IN ('time', 'datetime2', 'datetimeoffset', 'varbinary', 'varchar', 'binary', 'char', 'nvarchar', 'nchar') THEN '(' + CASE WHEN p.max_length = -1 THEN 'max' ELSE CAST(p.max_length AS nvarchar(50)) END + ')' ELSE '' END + ')' AS Name
            FROM  
                sys.parameters AS p
                JOIN sys.types AS t ON p.system_type_id = t.system_type_id AND p.user_type_id = t.user_type_id
            WHERE
                p.object_id = OBJECT_ID(@StoredProcedure)
            ORDER BY
                p.parameter_id";

        var parameter = new SqlParameter("@StoredProcedure", storedProcedure);

        return LoadData(query, parameter);
    }

    private DataSet SqlQuery(string query, out int result)
    {
        using (var connection = new SqlConnection(_connectionString))
        using (var adapter = new SqlDataAdapter(query, connection))
        {
            var set = new DataSet();

            result = adapter.Fill(set);

            return set;
        }
    }

    private KeyValuePair<string, string> GetDefinition(string viewOrStoredProcedure)
    {
        const string query = @"SELECT
                 @ViewOrStoredProcedure AS Id
                ,m.definition AS Name
            FROM
                sys.objects AS o
                JOIN sys.sql_modules AS m ON o.object_id = m.object_id
            WHERE
                o.object_id = OBJECT_ID(@ViewOrStoredProcedure)";

        var parameter = new SqlParameter("@ViewOrStoredProcedure", viewOrStoredProcedure);

        return LoadData(query, parameter).First();
    }

    private IEnumerable<KeyValuePair<string, string>> LoadData(string query)
    {
        var entities = new List<KeyValuePair<string, string>>();

        using (var connection = new SqlConnection(_connectionString))
        using (var command = new SqlCommand(query, connection) { CommandType = CommandType.Text })
        {
            if (connection.State == ConnectionState.Closed)
            {
                connection.Open();
            }
            using (var reader = command.ExecuteReader())
            {
                while (reader.Read())
                {
                    yield return new KeyValuePair<string, string>(reader.GetString(0), reader.GetString(1));
                }
            }
        }
    }

    private IEnumerable<KeyValuePair<string, string>> LoadData(string query, params SqlParameter[] parameters)
    {
        var entities = new List<KeyValuePair<string, string>>();

        using (var connection = new SqlConnection(_connectionString))
        using (var command = new SqlCommand(query, connection) { CommandType = CommandType.Text })
        {
            command.Parameters.AddRange(parameters);

            if (connection.State == ConnectionState.Closed)
            {
                connection.Open();
            }

            using (var reader = command.ExecuteReader())
            {
                while (reader.Read())
                {
                    yield return new KeyValuePair<string, string>(reader.GetString(0), reader.GetString(1));
                }
            }
        }
    }

    private void Export_Click(object sender, EventArgs e)
    {
        ErrorLabel.Text = null;
        ReturnLabel.Text = null;
        Results.Controls.Clear();

        if (string.IsNullOrWhiteSpace(Query.Text))
        {
            ErrorLabel.Text = "Query cannot be blank";
            return;
        }

        DataSet set;
        try
        {
            int result;
            set = SqlQuery(Query.Text, out result);
            ReturnLabel.Text = string.Format("({0} row(s) affected)", result);
        }
        catch (SqlException ex)
        {
            ErrorLabel.Text = ex.Message;
            return;
        }
        if (set.Tables.Count == 0)
        {
            ErrorLabel.Text = "Query returned no result";
            return;
        }
        var table = set.Tables[0];
        if (table.Rows.Count == 0)
        {
            ErrorLabel.Text = "Query returned no result";
            return;
        }

        var stringBuilder = new StringBuilder();

        var columns = table.Columns.Cast<DataColumn>().Select(column => column.ColumnName);
        stringBuilder.AppendLine(string.Join(",", columns));

        foreach (DataRow row in table.Rows)
        {
            var line = string.Join(",", row.ItemArray.Select(i => i is string ? string.Format("\"{0}\"", (i as string).Replace("\"", "\"\"")) : i));
            stringBuilder.AppendLine(line);
        }

        Response.Clear();
        Response.ContentType = "text/csv";
        Response.AddHeader("Content-Disposition", string.Format("attachment; filename={0}.csv", table.TableName));
        Response.Write(stringBuilder);
        Response.End();
    }
</script>

<html>
<head runat="server">
    <title>SQL Administrator</title>
    <style>
        body {
            margin: 10px;
            font-family: sans-serif;
            font-size: 12px;
        }

        #treeview-pane {
            width: 300px;
            overflow: auto;
            display: inline-block;
            vertical-align: top;
            margin-right: 10px;
        }

        #query-pane {
            width: calc(100% - 320px);
            overflow: auto;
            display: inline-block;
            vertical-align: top;
        }

            #query-pane textarea {
                width: calc(100% - 10px);
                height: 200px;
                resize: vertical;
            }

            #query-pane table {
                margin-bottom: 1em;
            }

        .error {
            color: red;
        }

        .success {
            color: blue;
        }
    </style>
</head>
<body>
    <form runat="server">
        <asp:ScriptManager runat="server" />
        <asp:UpdatePanel runat="server" UpdateMode="Conditional">
            <Triggers>
                <asp:PostBackTrigger ControlID="Export" />
            </Triggers>
            <ContentTemplate>
                <div id="treeview-pane">
                    <asp:TreeView ID="Tree" runat="server" OnTreeNodePopulate="Tree_TreeNodePopulate" OnSelectedNodeChanged="Tree_SelectedNodeChanged">
                        <Nodes>
                            <asp:TreeNode Text="Tables" Value="TABLE" PopulateOnDemand="true" SelectAction="None" Expanded="false" />
                            <asp:TreeNode Text="Views" Value="VIEW" PopulateOnDemand="true" SelectAction="None" Expanded="false" />
                            <asp:TreeNode Text="Stored Procedures" Value="SPROC" PopulateOnDemand="true" SelectAction="None" Expanded="false" />
                        </Nodes>
                    </asp:TreeView>
                    <p>
                        <asp:Button ID="Refresh" runat="server" Text="Refresh" OnClick="Refresh_Click" />
                    </p>
                </div>
                <div id="query-pane">
                    <asp:TextBox ID="Query" runat="server" TextMode="MultiLine" Wrap="false" />
                    <p>
                        <asp:Button ID="Execute" runat="server" Text="Execute" OnClick="Execute_Click" />
                        <asp:Button ID="Export" runat="server" Text="Export" OnClick="Export_Click" />
                        <asp:Button ID="Reset" runat="server" Text="Reset" OnClick="Reset_Click" />
                    </p>
                    <p>
                        <asp:Label ID="ErrorLabel" runat="server" CssClass="error" />
                        <asp:Label ID="ReturnLabel" runat="server" CssClass="success" />
                    </p>
                    <asp:Panel ID="Results" runat="server" />
                </div>
            </ContentTemplate>
        </asp:UpdatePanel>
    </form>
</body>
</html>
