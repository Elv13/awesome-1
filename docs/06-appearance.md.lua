#! /usr/bin/lua
local args = {...}

local gio = require("lgi").Gio
local gobject = require("lgi").GObject
local glib = require("lgi").GLib

local name_attr = gio.FILE_ATTRIBUTE_STANDARD_NAME

-- Recursive file scanner
local function get_all_files(path, ext, ret)
    ret = ret or {}
    local enumerator, _ = gio.File.new_for_path(path):enumerate_children(
        "FILE_ATTRIBUTE_STANDARD_NAME", 0, nil, nil
    )

    for file in function() return enumerator:next_file() end do
        local file_name = file:get_attribute_as_string(name_attr)
        local file_type = file:get_file_type()
        if file_type == "REGULAR" and file_name:match(ext or "") then
            table.insert(ret, path..file_name)
        elseif file_type == "DIRECTORY" then
            get_all_files(path..file_name.."/", ext, ret)
        end
    end

    return ret
end

local all_files = get_all_files("./lib/", "lua")

local beautiful_vars = {}

-- Find all @beautiful doc entries
for _,file in ipairs(all_files) do
    local f = io.open(file)

    local buffer = ""

    for line in function() return f:read("*line") end do

        local var = line:gmatch("--[ ]*@beautiful ([^ \n]*)")()

        -- There is no backward/forward pattern in lua
        if #line <= 1 then
            buffer = ""
        elseif #buffer and not var then
            buffer = buffer.."\n"..line
        elseif line:sub(1,3) == "---" then
            buffer = line
        end


        if var then

            -- Get the @param, @see and @usage
            local params = ""
            for line in function() return f:read("*line") end do
                if line:sub(1,2) ~= "--" then
                    break
                else
                    params = params.."\n"..line
                end
            end

            table.insert(beautiful_vars, {
                file = file,
                name = var:gmatch("[. ](.+)")(),
                link = "<a href='../classes/key.html'>"
                    .. var:gmatch("[. ](.+)")() ..
                "</a>",
                desc = buffer:gmatch("[- ]+([^\n.]*)")() or "",
                mod  =table.concat(
                    {file:gmatch("/([^/]+)/([^/]+)/([^/]+)%.lua")()}, '.'
                )
            })

            buffer = ""
        end
    end
end

local function create_table(entries, columns)
    local lines = {}

    for _, entry in ipairs(entries) do
        local line = "  <tr>"

        for _, column in ipairs(columns) do
            line = line.."<td>"..entry[column].."</td>"
        end

        table.insert(lines, line.."</tr>\n")
    end

    return [[<br \><br \><table class='widget_list' border=1>
 <tr style='font-weight: bold;'>
  <th align='center'>Name</th>
  <th align='center'>Description</th>
 </tr>]] .. table.concat(lines) .. "</table>\n"
end

-- Create the file
local filename = args[1]

local f = io.open(filename, "w")

f:write[[
# Change Awesome appareance

## The beautiful themes

Beautiful is where Awesome theme variables are stored.

]]

f:write(create_table(beautiful_vars, {"link", "desc"}))

f:close()

--TODO add some linting to direct undeclared beautiful variables
--TODO re-generate all official themes
--TODO generate a complete sample theme
