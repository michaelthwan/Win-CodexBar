-- Parses the desktop app's status-pipe snapshot and lays out one group per provider:
-- a header (logo, name, data age) followed by one row per quota window.
-- Snapshot shape (camelCase): {"providers":[{"id","name","primaryLabel","primary":{...},
-- "secondaryLabel","secondary":{...}|null,"error":string|null,"updatedAt"}]}

local PROVIDERS = {
  { id = 'claude', name = 'Claude', bar = '204,124,94,255' },
  { id = 'codex', name = 'Codex', bar = '73,163,176,255' },
  { id = 'grok', name = 'Grok', bar = '215,215,215,255' },
}
local TOP = 38          -- first group header
local HEADER_H = 20     -- header row height
local ROW_H = 18        -- quota row height
local GROUP_GAP = 8     -- space above a separator between groups
local BAR_WIDTH = 170

local maxGroups, maxRows, statusMeasure, utcOffset

function Initialize()
  maxGroups = SELF:GetNumberOption('MaxGroups', 3)
  maxRows = SELF:GetNumberOption('MaxRows', 8)
  statusMeasure = SKIN:GetMeasure('MeasureStatus')
  local now = os.time()
  utcOffset = os.difftime(now, os.time(os.date('!*t', now)))
end

-- Names windows by length so providers read alike; falls back to the
-- provider's own label for irregular windows.
local function windowLabel(minutes, explicit)
  minutes = tonumber(minutes) or 0
  if minutes <= 0 or (minutes % 60 ~= 0) then return explicit or 'Quota' end
  if minutes == 300 then return '5-hour' end
  if minutes == 1440 then return 'Daily' end
  if minutes == 10080 then return 'Weekly' end
  if minutes >= 40320 and minutes <= 44640 then return 'Monthly' end
  if minutes % 1440 == 0 then return math.floor(minutes / 1440) .. '-day' end
  return math.floor(minutes / 60) .. '-hour'
end

local function parseUtc(iso)
  local y, mo, d, h, mi, s = (iso or ''):match('(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
  if not y then return nil end
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false })
  return t + utcOffset
end

local function duration(seconds)
  local days = math.floor(seconds / 86400)
  local hours = math.floor((seconds % 86400) / 3600)
  local mins = math.floor((seconds % 3600) / 60)
  if days > 0 then return string.format('%dd %dh', days, hours) end
  if hours > 0 then return string.format('%dh %dm', hours, mins) end
  return string.format('%dm', math.max(mins, 1))
end

local function field(obj, key)
  return obj:match('"' .. key .. '"%s*:%s*"([^"]*)"')
end

local function number(obj, key)
  return tonumber(obj:match('"' .. key .. '"%s*:%s*(-?[%d%.]+)'))
end

local function windowRow(window, explicitLabel)
  if not window or window:match('"isInformational"%s*:%s*true') then return nil end
  local used = number(window, 'usedPercent')
  if not used then return nil end
  local text = windowLabel(number(window, 'windowMinutes'), explicitLabel)
  local resetAt = parseUtc(field(window, 'resetsAt'))
  local left
  if resetAt then
    local secs = os.difftime(resetAt, os.time())
    left = secs > 0 and duration(secs) or 'now'
  else
    left = field(window, 'resetDescription')
  end
  if left then text = text .. '  ' .. left end
  return {
    label = text,
    value = string.format('%d%%', math.floor(used + 0.5)),
    percent = used,
    tip = resetAt and ('Resets ' .. os.date('%a %d %b %H:%M', resetAt)) or '',
  }
end

-- Returns the group list, or nil plus a status message when there is nothing to show.
local function parseSnapshot(body)
  if body == nil or body == '' then return nil, 'Waiting for CodexBar...' end
  local list = body:match('"providers"%s*:%s*(%b[])')
  if not list then
    return nil, field(body, 'error') or 'Unexpected response from CodexBar'
  end

  local byId = {}
  for obj in list:gmatch('%b{}') do
    local id = field(obj, 'id')
    if id then byId[id] = obj end
  end

  local groups = {}
  for _, p in ipairs(PROVIDERS) do
    local obj = byId[p.id]
    if obj then
      local group = { provider = p, rows = {}, error = field(obj, 'error') }
      local updated = parseUtc(field(obj, 'updatedAt'))
      if updated then group.age = duration(math.max(os.difftime(os.time(), updated), 60)) .. ' ago' end
      for _, slot in ipairs({ 'primary', 'secondary' }) do
        local row = windowRow(obj:match('"' .. slot .. '"%s*:%s*(%b{})'), field(obj, slot .. 'Label'))
        if row then table.insert(group.rows, row) end
      end
      if #group.rows == 0 then
        group.rows[1] = { label = 'No quota reported', value = '', percent = nil, tip = group.error or '' }
      end
      table.insert(groups, group)
    end
  end
  if #groups == 0 then return nil, 'Enable Claude, Codex or Grok in CodexBar' end
  return groups
end

local function show(meter, visible)
  SKIN:Bang(visible and '!ShowMeter' or '!HideMeter', meter)
end

local function placeHeader(i, group, y)
  local p = group.provider
  show('MeterSep' .. i, i > 1)
  SKIN:Bang('!SetOption', 'MeterSep' .. i, 'Y', y - GROUP_GAP / 2 - 1)
  SKIN:Bang('!SetOption', 'MeterIcon' .. i, 'ImageName', '#@#icons\\' .. p.id .. '.png')
  SKIN:Bang('!SetOption', 'MeterIcon' .. i, 'Y', y)
  SKIN:Bang('!SetOption', 'MeterName' .. i, 'Text', p.name)
  SKIN:Bang('!SetOption', 'MeterName' .. i, 'Y', y)
  local age = group.error and 'refresh failed' or (group.age or '')
  SKIN:Bang('!SetOption', 'MeterAge' .. i, 'Text', age)
  SKIN:Bang('!SetOption', 'MeterAge' .. i, 'ToolTipText', group.error or '')
  SKIN:Bang('!SetOption', 'MeterAge' .. i, 'Y', y + 1)
  for _, m in ipairs({ 'MeterIcon', 'MeterName', 'MeterAge' }) do show(m .. i, true) end
end

local function placeRow(i, row, color, y)
  local label, value, bar = 'MeterRowLabel' .. i, 'MeterRowValue' .. i, 'MeterRowBar' .. i
  SKIN:Bang('!SetOption', label, 'Text', row.label)
  SKIN:Bang('!SetOption', label, 'ToolTipText', row.tip or '')
  SKIN:Bang('!SetOption', label, 'Y', y)
  SKIN:Bang('!SetOption', value, 'Text', row.value)
  SKIN:Bang('!SetOption', value, 'Y', y)
  SKIN:Bang('!SetOption', bar, 'Y', y + 12)
  local pct = math.max(0, math.min(row.percent or 0, 100))
  local fill = pct >= 90 and '#colorHot#' or color
  SKIN:Bang('!SetOption', bar, 'Shape2', string.format(
    'Rectangle 0,0,%.1f,1 | Fill Color %s | StrokeWidth 0', math.max(BAR_WIDTH * pct / 100, 0.1), fill))
  show(label, true)
  show(value, true)
  show(bar, row.percent ~= nil)
end

function Update()
  local groups, status = parseSnapshot(statusMeasure:GetStringValue())
  groups = groups or {}

  local y, rowIndex, shownGroups = TOP, 0, 0
  for gi = 1, maxGroups do
    local group = groups[gi]
    if group and rowIndex < maxRows then
      if gi > 1 then y = y + GROUP_GAP end
      placeHeader(gi, group, y)
      y = y + HEADER_H
      for _, row in ipairs(group.rows) do
        if rowIndex >= maxRows then break end
        rowIndex = rowIndex + 1
        placeRow(rowIndex, row, group.provider.bar, y)
        y = y + ROW_H
      end
      shownGroups = gi
    else
      for _, m in ipairs({ 'MeterSep', 'MeterIcon', 'MeterName', 'MeterAge' }) do show(m .. gi, false) end
    end
  end
  for ri = rowIndex + 1, maxRows do
    for _, m in ipairs({ 'MeterRowLabel', 'MeterRowValue', 'MeterRowBar' }) do show(m .. ri, false) end
  end

  if shownGroups == 0 then
    SKIN:Bang('!SetOption', 'MeterStatus', 'Text', status)
    show('MeterStatus', true)
    y = TOP + 36
  else
    show('MeterStatus', false)
  end

  SKIN:Bang('!SetOption', 'MeterBackground', 'Shape', string.format(
    'Rectangle 0.5,0.5,209,%d,6 | Fill Color 0,0,0,170 | StrokeWidth 1 | Stroke Color 255,255,255,40', y + 4))
  return rowIndex
end
