local fs   = require "nixio.fs"
local nw   = require "luci.model.network"
local fw   = require "luci.model.firewall"
local uci  = require "luci.model.uci".cursor()
local http = require "luci.http"
local e = require"luci.http"

local iw = luci.sys.wifi.getiwinfo(http.formvalue("device"))

local has_firewall = fs.access("/etc/config/firewall")

if not iw then
	luci.http.redirect(luci.dispatcher.build_url("admin/network/wireless"))
	return
end

m=SimpleForm("network",translatef("Joining Network: %q",e.formvalue("join")))
m.cancel = translate("Back to scan results")
m.reset = false

function m.on_cancel()
	local dev = http.formvalue("device")
	http.redirect(luci.dispatcher.build_url(
		dev and "admin/network/wireless_join?device=" .. dev
			or "admin/network/wireless"
	))
end

nw.init(uci)
fw.init(uci)

m.hidden = {
	device      = http.formvalue("device"),
	join        = http.formvalue("join"),
	channel     = http.formvalue("channel"),
	mode        = http.formvalue("mode"),
	bssid       = http.formvalue("bssid"),
	wep         = http.formvalue("wep"),
	wpa_suites	= http.formvalue("wpa_suites"),
	wpa_version = http.formvalue("wpa_version")
}


if http.formvalue("wep") == "1" then
	--key = m:field(Value, "key", translate("WEP passphrase"),
	--	translate("Specify the secret encryption key here."))
	key = m:field(Value, "key", translate("WEP passphrase"))

	key.password = true
	key.datatype = "wepkey"

elseif (tonumber(m.hidden.wpa_version) or 0) > 0 and
	(m.hidden.wpa_suites == "PSK" or m.hidden.wpa_suites == "PSK2")
then
        key = m:field(Value, "key", translate("WPA passphrase"))

	key.password = true
	key.datatype = "wpakey"
	--m.hidden.wpa_suite = (tonumber(http.formvalue("wpa_version")) or 0) >= 2 and "psk2" or "psk"
end


newnet = m:field(DummyValue, "_netname_new", translate("Name of the new network"))

newnet.default = "wwan"
newnet.datatype = "uciname"

if has_firewall then
	fwzone.default = m.hidden.mode == "Ad-Hoc" and "mesh" or "wan"
	
end

function newnet.parse(self, section)
	local net, zone

	if has_firewall then
		local zval  = "wan"
		zone = fw:get_zone(zval)

		if not zone and zval == '-' then
			--zval = m:formvalue(fwzone:cbid(section) .. ".newzone")
			zval = m:formvalue(fwzone:cbid("wwan") .. ".newzone")
			if zval and #zval > 0 then
				zone = fw:add_zone(zval)
			end
		end
	end

	local wdev = nw:get_wifidev(m.hidden.device)

	wdev:set("disabled", false)
	wdev:set("channel", m.hidden.channel)

	if "1" then
		local n
		for _, n in ipairs(wdev:get_wifinets()) do
			wdev:del_wifinet(n)
		end
	end

	local wconf = {
		device  = m.hidden.device,
		ssid    = m.hidden.join,
		mode    = (m.hidden.mode == "Ad-Hoc" and "adhoc" or "sta")
	}

	if m.hidden.wep == "1" then
		wconf.encryption = "wep-open"
		wconf.key        = "1"
		wconf.key1       = key and key:formvalue(section) or ""
	elseif (tonumber(m.hidden.wpa_version) or 0) > 0 then
		wconf.encryption = (tonumber(m.hidden.wpa_version) or 0) >= 2 and "psk2" or "psk"
		wconf.key        = key and key:formvalue(section) or ""
	else
		wconf.encryption = "none"
	end

	if wconf.mode == "adhoc" or wconf.mode == "sta" then
		wconf.bssid = m.hidden.bssid
	end

	local value = "wwan"
	net = nw:add_network(value, { proto = "dhcp" })
        
	if not net then
		self.error = { [section] = "missing" }
	else
		wconf.network = net:name()

		local wnet = wdev:add_wifinet(wconf)
		if wnet then
			if zone then
				fw:del_network(net:name())
				zone:add_network(net:name())
			end

			uci:save("wireless")
			uci:save("network")
			uci:save("firewall")
			uci:commit("wireless")
			uci:commit("network")
			uci:commit("firewall")
			uci:apply("wireless")
			uci:apply("network")
			uci:apply("firewall")

			luci.http.redirect(luci.dispatcher.build_url("admin","network","wireless"))

		end
	end
end

if has_firewall then
	function fwzone.cfgvalue(self, section)
		self.iface = section
		local z = fw:get_zone_by_network(section)
		return z and z:name()
	end
end

return m
