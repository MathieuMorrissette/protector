minetest.register_privilege("delprotect","Ignore player protection")

protector = {}
protector.radius = (tonumber(minetest.setting_get("protector_radius")) or 5)

protector.get_member_list = function(meta)
	return meta:get_string("members"):split(" ")
end

protector.set_member_list = function(meta, list)
	meta:set_string("members", table.concat(list, " "))
end

protector.is_member = function (meta, name)
	for _, n in ipairs(protector.get_member_list(meta)) do
		if n == name then
			return true
		end
	end
	return false
end

protector.add_member = function(meta, name)
	if protector.is_member(meta, name) then return end
	local list = protector.get_member_list(meta)
	table.insert(list,name)
	protector.set_member_list(meta,list)
end

protector.del_member = function(meta,name)
	local list = protector.get_member_list(meta)
	for i, n in ipairs(list) do
		if n == name then
			table.remove(list, i)
			break
		end
	end
	protector.set_member_list(meta,list)
end

-- Protector Interface

protector.generate_formspec = function(meta)

	local formspec = "size[8,7]"..default.gui_bg..default.gui_bg_img..default.gui_slots
		.."label[2.5,0;-- Protector interface --]"
		.."label[0,1;PUNCH node to show protected area or USE for area check]"
		.."label[0,2;Members: (type player name then press Enter to add)]"

	local members = protector.get_member_list(meta)
	local npp = 12
	local i = 0

	for _, member in ipairs(members) do
			if i < npp then
				formspec = formspec .. "button["..(i%4*2)..","
				..math.floor(i/4+3)..";1.5,.5;protector_member;"..member.."]"
				formspec = formspec .. "button["..(i%4*2+1.25)..","
				..math.floor(i/4+3)..";.75,.5;protector_del_member_"..member..";X]"
			end
			i = i +1
	end
	
	if i < npp then
		formspec = formspec
		.."field["..(i%4*2+1/3)..","..(math.floor(i/4+3)+1/3)..";1.433,.5;protector_add_member;;]"
	end

	formspec = formspec.."button_exit[2.5,6.2;3,0.5;close_me;Close]"

	return formspec
end

-- ACTUAL PROTECTION SECTION

-- Infolevel:
-- 0 for no info
-- 1 for "This area is owned by <owner> !" if you can't dig
-- 2 for "This area is owned by <owner>.
-- 3 for checking protector overlaps

protector.can_dig = function(r,pos,digger,onlyowner,infolevel)

	if not digger then
		return false
	end

	-- Delprotect privileged users can override protections

	if minetest.check_player_privs(digger, {delprotect=true}) and infolevel == 1 then
		return true
	end

	if infolevel == 3 then infolevel = 1 end

	-- Find the protector nodes

	local positions = minetest.find_nodes_in_area(
		{x=pos.x-r, y=pos.y-r, z=pos.z-r},
		{x=pos.x+r, y=pos.y+r, z=pos.z+r},
		{"protector:protect", "protector:protect2"})

	if #positions > 0 then
		local meta = minetest.get_meta(positions[1])
		local owner = meta:get_string("owner")
		local members = meta:get_string("members")

		if owner ~= digger then 
			if onlyowner or not protector.is_member(meta, digger) then
				if infolevel == 1 then
					minetest.chat_send_player(digger,"This area is owned by "..owner.." !")
				elseif infolevel == 2 then
					minetest.chat_send_player(digger,"This area is owned by "..owner..".")
					minetest.chat_send_player(digger,"Protection located at: "..minetest.pos_to_string(positions[1]))
					if members ~= "" then
						minetest.chat_send_player(digger,"Members: "..members..".")
					end
				end
				return false
			end
		end

		if infolevel == 2 then
			minetest.chat_send_player(digger,"This area is owned by "..owner..".")
			minetest.chat_send_player(digger,"Protection located at: "..minetest.pos_to_string(positions[1]))
			if members ~= "" then
				minetest.chat_send_player(digger,"Members: "..members..".")
			end
		end

	end

	if infolevel == 2 then
		if #positions < 1 then
			minetest.chat_send_player(digger,"This area is not protected.")
		end
		minetest.chat_send_player(digger,"You can build here.")
	end

	return true
end

-- Can node be added or removed, if so return node else true (for protected)

protector.old_is_protected = minetest.is_protected
minetest.is_protected = function(pos, digger)

	if protector.can_dig(protector.radius, pos, digger, false, 1) then
		return protector.old_is_protected(pos, digger)
	else
		return true
	end
end

-- Make sure protection block doesn't overlap another protector's area

protector.old_node_place = minetest.item_place
function minetest.item_place(itemstack, placer, pointed_thing)

	if itemstack:get_name() == "protector:protect" or itemstack:get_name() == "protector:protect2" then
		local pos = pointed_thing.above
		local user = placer:get_player_name()
		if not protector.can_dig(protector.radius * 2, pos, user, true, 3) then
			minetest.chat_send_player(user, "Overlaps into another protected area")
			return protector.old_node_place(itemstack, placer, pos)
		end
	end

	return protector.old_node_place(itemstack, placer, pointed_thing)
end

-- END

--= Protection Block

minetest.register_node("protector:protect", {
	description = "Protection Block",
	tiles = {"moreblocks_circle_stone_bricks.png","moreblocks_circle_stone_bricks.png","moreblocks_circle_stone_bricks.png^protector_logo.png"},
	sounds = default.node_sound_stone_defaults(),
	groups = {dig_immediate=2},
	drawtype = "nodebox",
	node_box = {
		type="fixed",
		fixed = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
	},
	selection_box = { type="regular" },
	paramtype = "light",
	light_source = 2,

	after_place_node = function(pos, placer)
		local meta = minetest.get_meta(pos)
		meta:set_string("owner", placer:get_player_name() or "")
		meta:set_string("infotext", "Protection (owned by "..meta:get_string("owner")..")")
		meta:set_string("members", "")
	end,

	on_use = function(itemstack, user, pointed_thing)
		if pointed_thing.type ~= "node" then return end
		protector.can_dig(protector.radius,pointed_thing.under,user:get_player_name(),false,2)
	end,

	on_rightclick = function(pos, node, clicker, itemstack)
		local meta = minetest.get_meta(pos)
		if protector.can_dig(1,pos,clicker:get_player_name(),true,1) then
			minetest.show_formspec(clicker:get_player_name(), 
			"protector:node_"..minetest.pos_to_string(pos), protector.generate_formspec(meta))
		end
	end,

	on_punch = function(pos, node, puncher)
		if not protector.can_dig(1,pos,puncher:get_player_name(),true,1) then
			return
		end
		minetest.add_entity(pos, "protector:display")
	end,
})

minetest.register_craft({
	output = "protector:protect 4",
	recipe = {
		{"default:stone","default:stone","default:stone"},
		{"default:stone","default:steel_ingot","default:stone"},
		{"default:stone","default:stone","default:stone"},
	}
})

--= Protection Logo

minetest.register_node("protector:protect2", {
	description = "Protection Logo",
	tiles = {"protector_logo.png"},
	wield_image = "protector_logo.png",
	inventory_image = "protector_logo.png",
	sounds = default.node_sound_stone_defaults(),
	groups = {dig_immediate=2},
	paramtype = 'light',
	paramtype2 = "wallmounted",
	light_source = 2,
	drawtype = "nodebox",
	sunlight_propagates = true,
	walkable = true,
	node_box = {
		type = "wallmounted",
		wall_top    = {-0.375, 0.4375, -0.5, 0.375, 0.5, 0.5},
		wall_bottom = {-0.375, -0.5, -0.5, 0.375, -0.4375, 0.5},
		wall_side   = {-0.5, -0.5, -0.375, -0.4375, 0.5, 0.375},
	},
	selection_box = {type = "wallmounted"},

	after_place_node = function(pos, placer)
		local meta = minetest.get_meta(pos)
		meta:set_string("owner", placer:get_player_name() or "")
		meta:set_string("infotext", "Protection (owned by "..meta:get_string("owner")..")")
		meta:set_string("members", "")
	end,

	on_use = function(itemstack, user, pointed_thing)
		if pointed_thing.type ~= "node" then return end
		protector.can_dig(protector.radius,pointed_thing.under,user:get_player_name(),false,2)
	end,

	on_rightclick = function(pos, node, clicker, itemstack)
		local meta = minetest.get_meta(pos)
		if protector.can_dig(1,pos,clicker:get_player_name(),true,1) then
			minetest.show_formspec(clicker:get_player_name(), 
			"protector:node_"..minetest.pos_to_string(pos), protector.generate_formspec(meta))
		end
	end,

	on_punch = function(pos, node, puncher)
		if not protector.can_dig(1,pos,puncher:get_player_name(),true,1) then
			return
		end
		minetest.add_entity(pos, "protector:display")
	end,
})

minetest.register_craft({
	output = "protector:protect2 4",
	recipe = {
		{"default:stone","default:stone","default:stone"},
		{"default:stone","default:copper_ingot","default:stone"},
		{"default:stone","default:stone","default:stone"},
	}
})

-- If name entered or button press
minetest.register_on_player_receive_fields(function(player,formname,fields)

	if string.sub(formname,0,string.len("protector:node_")) == "protector:node_" then

		local pos_s = string.sub(formname,string.len("protector:node_")+1)
		local pos = minetest.string_to_pos(pos_s)
		local meta = minetest.get_meta(pos)

		if not protector.can_dig(1,pos,player:get_player_name(),true,1) then
			return
		end

		if fields.protector_add_member then
			for _, i in ipairs(fields.protector_add_member:split(" ")) do
				protector.add_member(meta,i)
			end
		end

		for field, value in pairs(fields) do
			if string.sub(field,0,string.len("protector_del_member_"))=="protector_del_member_" then
				protector.del_member(meta, string.sub(field,string.len("protector_del_member_")+1))
			end
		end
		
		if not fields.close_me then
			minetest.show_formspec(player:get_player_name(), formname, protector.generate_formspec(meta))
		end

	end

end)

minetest.register_entity("protector:display", {
	physical = false,
	collisionbox = {0,0,0,0,0,0},
	visual = "wielditem",
	visual_size = {x=1.0/1.5,y=1.0/1.5}, -- wielditem seems to be scaled to 1.5 times original node size
	textures = {"protector:display_node"},
	on_step = function(self, dtime)
		self.timer = (self.timer or 0) + dtime
		if self.timer > 10 then
			self.object:remove()
		end
	end,
})

-- Display-zone node, Do NOT place the display as a node, it is made to be used as an entity (see above)
local x = protector.radius
minetest.register_node("protector:display_node", {
	tiles = {"protector_display.png"},
	use_texture_alpha = true,
	walkable = false,
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			-- sides
			{-(x+.55), -(x+.55), -(x+.55), -(x+.45), (x+.55), (x+.55)},
			{-(x+.55), -(x+.55), (x+.45), (x+.55), (x+.55), (x+.55)},
			{(x+.45), -(x+.55), -(x+.55), (x+.55), (x+.55), (x+.55)},
			{-(x+.55), -(x+.55), -(x+.55), (x+.55), (x+.55), -(x+.45)},
			-- top
			{-(x+.55), (x+.45), -(x+.55), (x+.55), (x+.55), (x+.55)},
			-- bottom
			{-(x+.55), -(x+.55), -(x+.55), (x+.55), -(x+.45), (x+.55)},
			-- middle (surround protector)
			{-.55,-.55,-.55, .55,.55,.55},
		},
	},
	selection_box = {
		type = "regular",
	},
	paramtype = "light",
	groups = {dig_immediate=3,not_in_creative_inventory=1},
	drop = "",
})

-- Register Protected Doors

local function on_rightclick(pos, dir, check_name, replace, replace_dir, params)
	pos.y = pos.y+dir
	if not minetest.get_node(pos).name == check_name then
		return
	end
	local p2 = minetest.get_node(pos).param2
	p2 = params[p2+1]
		
	minetest.swap_node(pos, {name=replace_dir, param2=p2})
		
	pos.y = pos.y-dir
	minetest.swap_node(pos, {name=replace, param2=p2})

	local snd_1 = "doors_door_close"
	local snd_2 = "doors_door_open" 
	if params[1] == 3 then
		snd_1 = "doors_door_open"
		snd_2 = "doors_door_close"
	end

	if minetest.get_meta(pos):get_int("right") ~= 0 then
		minetest.sound_play(snd_1, {pos = pos, gain = 0.3, max_hear_distance = 10})
	else
		minetest.sound_play(snd_2, {pos = pos, gain = 0.3, max_hear_distance = 10})
	end
end

-- Protected Wooden Door

local name = "protector:door_wood"

doors.register_door(name, {
	description = "Protected Wooden Door",
	inventory_image = "doors_wood.png^protector_logo.png",
	groups = {snappy=1,choppy=2,oddly_breakable_by_hand=2,flammable=2,door=1},
	tiles_bottom = {"doors_wood_b.png^protector_logo.png", "doors_brown.png"},
	tiles_top = {"doors_wood_a.png", "doors_brown.png"},
	sounds = default.node_sound_wood_defaults(),
	sunlight = false,
})

minetest.override_item(name.."_b_1", {
	on_rightclick = function(pos, node, clicker)
		if not minetest.is_protected(pos, clicker:get_player_name()) then
			on_rightclick(pos, 1, name.."_t_1", name.."_b_2", name.."_t_2", {1,2,3,0})
		end
	end,
})

minetest.override_item(name.."_t_1", {
	on_rightclick = function(pos, node, clicker)
		if not minetest.is_protected(pos, clicker:get_player_name()) then
			on_rightclick(pos, -1, name.."_b_1", name.."_t_2", name.."_b_2", {1,2,3,0})
		end
	end,
})

minetest.override_item(name.."_b_2", {
	on_rightclick = function(pos, node, clicker)
		if not minetest.is_protected(pos, clicker:get_player_name()) then
			on_rightclick(pos, 1, name.."_t_2", name.."_b_1", name.."_t_1", {3,0,1,2})
		end
	end,
})

minetest.override_item(name.."_t_2", {
	on_rightclick = function(pos, node, clicker)
		if not minetest.is_protected(pos, clicker:get_player_name()) then
			on_rightclick(pos, -1, name.."_b_2", name.."_t_1", name.."_b_1", {3,0,1,2})
		end
	end,
})

minetest.register_craft({
	output = name,
	recipe = {
		{"group:wood", "group:wood"},
		{"group:wood", "default:copper_ingot"},
		{"group:wood", "group:wood"}
	}
})

minetest.register_craft({
	output = name,
	recipe = {
		{"doors:door_wood", "default:copper_ingot"}
	}
})

-- Protected Steel Door

local name = "protector:door_steel"

doors.register_door(name, {
	description = "Protected Steel Door",
	inventory_image = "doors_steel.png^protector_logo.png",
	groups = {snappy=1,bendy=2,cracky=1,melty=2,level=2,door=1},
	tiles_bottom = {"doors_steel_b.png^protector_logo.png", "doors_grey.png"},
	tiles_top = {"doors_steel_a.png", "doors_grey.png"},
	sounds = default.node_sound_wood_defaults(),
	sunlight = false,
})

minetest.override_item(name.."_b_1", {
	on_rightclick = function(pos, node, clicker)
		if not minetest.is_protected(pos, clicker:get_player_name()) then
			on_rightclick(pos, 1, name.."_t_1", name.."_b_2", name.."_t_2", {1,2,3,0})
		end
	end,
})

minetest.override_item(name.."_t_1", {
	on_rightclick = function(pos, node, clicker)
		if not minetest.is_protected(pos, clicker:get_player_name()) then
			on_rightclick(pos, -1, name.."_b_1", name.."_t_2", name.."_b_2", {1,2,3,0})
		end
	end,
})

minetest.override_item(name.."_b_2", {
	on_rightclick = function(pos, node, clicker)
		if not minetest.is_protected(pos, clicker:get_player_name()) then
			on_rightclick(pos, 1, name.."_t_2", name.."_b_1", name.."_t_1", {3,0,1,2})
		end
	end,
})

minetest.override_item(name.."_t_2", {
	on_rightclick = function(pos, node, clicker)
		if not minetest.is_protected(pos, clicker:get_player_name()) then
			on_rightclick(pos, -1, name.."_b_2", name.."_t_1", name.."_b_1", {3,0,1,2})
		end
	end,
})

minetest.register_craft({
	output = name,
	recipe = {
		{"default:steel_ingot", "default:steel_ingot"},
		{"default:steel_ingot", "default:copper_ingot"},
		{"default:steel_ingot", "default:steel_ingot"}
	}
})

minetest.register_craft({
	output = name,
	recipe = {
		{"doors:door_steel", "default:copper_ingot"}
	}
})

-- Protected Chest

minetest.register_node("protector:chest", {
	description = "Protected Chest",
	tiles = {"default_chest_top.png", "default_chest_top.png", "default_chest_side.png",
		"default_chest_side.png", "default_chest_side.png", "default_chest_front.png^protector_logo.png"},
	paramtype2 = "facedir",
	groups = {choppy=2,oddly_breakable_by_hand=2},
	legacy_facedir_simple = true,
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", "Protected Chest")
		meta:set_string("name", "")
		local inv = meta:get_inventory()
		inv:set_size("main", 8*4)
	end,
	can_dig = function(pos,player)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		if inv:is_empty("main") then
			if not minetest.is_protected(pos, player:get_player_name()) then
				return true
			end
		end
	end,
	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		return count
	end,
    allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		return stack:get_count()
	end,
    allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		return stack:get_count()
	end,
    on_metadata_inventory_put = function(pos, listname, index, stack, player)
		minetest.log("action", player:get_player_name()..
				" moves stuff to protected chest at "..minetest.pos_to_string(pos))
	end,
    on_metadata_inventory_take = function(pos, listname, index, stack, player)
		minetest.log("action", player:get_player_name()..
				" takes stuff from protected chest at "..minetest.pos_to_string(pos))
	end,
	on_rightclick = function(pos, node, clicker)
		local meta = minetest.get_meta(pos)
		if not minetest.is_protected(pos, clicker:get_player_name()) then

		local spos = pos.x .. "," .. pos.y .. "," ..pos.z
		local formspec = "size[8,9]"..
			default.gui_bg..default.gui_bg_img..default.gui_slots..
			"list[nodemeta:".. spos .. ";main;0,0.3;8,4;]"..
			"button[0,4.5;2,0.25;toup;To Chest]"..
			"field[2.3,4.8;4,0.25;chestname;;"..meta:get_string("name").."]"..
			"button[6,4.5;2,0.25;todn;To Inventory]"..
			"list[current_player;main;0,5;8,1;]"..
			"list[current_player;main;0,6.08;8,3;8]"..
			default.get_hotbar_bg(0,5)

			minetest.show_formspec(
				clicker:get_player_name(),
				"protector:chest_"..minetest.pos_to_string(pos),
				formspec
			)
		end
	end,
})

-- Protected Chest formspec buttons

minetest.register_on_player_receive_fields(function(player,formname,fields)

	if string.sub(formname,0,string.len("protector:chest_")) == "protector:chest_" then

		local pos_s = string.sub(formname,string.len("protector:chest_")+1)
		local pos = minetest.string_to_pos(pos_s)
		local meta = minetest.get_meta(pos)

		local chest_inv = meta:get_inventory()
		local player_inv = player:get_inventory()

		if fields.toup then

			-- copy contents of players inventory to chest
			for i,v in ipairs( player_inv:get_list( "main" ) or {}) do
				if( chest_inv and chest_inv:room_for_item('main', v)) then
					local leftover = chest_inv:add_item( 'main', v )
					player_inv:remove_item( "main", v )
					if( leftover and not( leftover:is_empty() )) then
						player_inv:add_item( "main", v )
					end
				end
			end
	
		elseif fields.todn then

			-- copy contents of chest to players inventory
			for i,v in ipairs( chest_inv:get_list( 'main' ) or {}) do
				if( player_inv:room_for_item( "main", v)) then
					local leftover = player_inv:add_item( "main", v )
					chest_inv:remove_item( 'main', v )
					if( leftover and not( leftover:is_empty() )) then
						chest_inv:add_item( 'main', v )
					end
				end
			end

		elseif fields.chestname then

			-- change chest infotext to display name
			if fields.chestname ~= "" then
				meta:set_string("name", fields.chestname)
				meta:set_string("infotext", "Protected Chest ("..fields.chestname..")")
			else
				meta:set_string("infotext", "Protected Chest")
			end

		end
	end

end)

-- Protected Chest recipe

minetest.register_craft({
	output = 'protector:chest',
	recipe = {
		{'group:wood', 'group:wood', 'group:wood'},
		{'group:wood', 'default:copper_ingot', 'group:wood'},
		{'group:wood', 'group:wood', 'group:wood'},
	}
})

--Protected shop---------------------------------------------------------------------------------------------------------
default.shop = {}
default.shop.current_shop = {}
default.shop.formspec = {
	customer = function(pos)
		local list_name = "nodemeta:"..pos.x..','..pos.y..','..pos.z
		local formspec = "size[8,9.5]"..
		"label[0,0;Customer gives (pay here !)]"..
		"list[current_player;customer_gives;0,0.5;3,2;]"..
		"label[0,2.5;Customer gets]"..
		"list[current_player;customer_gets;0,3;3,2;]"..
		"label[5,0;Owner wants]"..
		"list["..list_name..";owner_wants;5,0.5;3,2;]"..
		"label[5,2.5;Owner gives]"..
		"list["..list_name..";owner_gives;5,3;3,2;]"..
		"list[current_player;main;0,5.5;8,4;]"..
		"button[3,2;2,1;exchange;Exchange]"
		return formspec
	end,
	owner = function(pos)
		local list_name = "nodemeta:"..pos.x..','..pos.y..','..pos.z
		local formspec = "size[8,9.5]"..
		"label[0,0;Customers gave:]"..
		"list["..list_name..";customers_gave;0,0.5;3,2;]"..
		"label[0,2.5;Your stock:]"..
		"list["..list_name..";stock;0,3;3,2;]"..
		"label[5,0;You want:]"..
		"list["..list_name..";owner_wants;5,0.5;3,2;]"..
		"label[5,2.5;In exchange, you give:]"..
		"list["..list_name..";owner_gives;5,3;3,2;]"..
		"label[0,5;Owner, Use(E)+Place(RMB) for customer interface]"..
		"list[current_player;main;0,5.5;8,4;]"
		return formspec
	end,
}


minetest.register_craft({
	output = 'protector:shop',
	recipe = {
		{'default:sign_wall'},
		{'default:chest_locked'},
        {'default:copper_ingot'}
        
	}
})


minetest.register_node("protector:shop", {
	description = "Protected shop",
	paramtype2 = "facedir",
	tiles = {"protect_shop_top.png",
	                "protect_shop_top.png",
			"protect_shop_side.png",
			"protect_shop_side.png",
			"protect_shop_side.png",
			"protect_shop_front.png"},
	inventory_image = "protect_shop_front.png",
	groups = {choppy=2,oddly_breakable_by_hand=2},
	sounds = default.node_sound_wood_defaults(),
	after_place_node = function(pos, placer, itemstack)
		local owner = placer:get_player_name()
		local meta = minetest.env:get_meta(pos)
		meta:set_string("infotext", "Exchange shop (owned by "..owner..")")
		meta:set_string("owner",owner)
		--[[meta:set_string("pl1","")
		meta:set_string("pl2","")]]
		local inv = meta:get_inventory()
		inv:set_size("customers_gave", 3*2)
		inv:set_size("stock", 3*2)
		inv:set_size("owner_wants", 3*2)
		inv:set_size("owner_gives", 3*2)
	end,
	on_rightclick = function(pos, node, clicker, itemstack)
    
		clicker:get_inventory():set_size("customer_gives", 3*2)
		clicker:get_inventory():set_size("customer_gets", 3*2)
        
		default.shop.current_shop[clicker:get_player_name()] = pos
        
		local meta = minetest.env:get_meta(pos)
		if (clicker:get_player_name() == meta:get_string("owner")) or not minetest.is_protected(pos,clicker:get_player_name()) and not clicker:get_player_control().aux1 then
			minetest.show_formspec(clicker:get_player_name(),"protector:shop_formspec",default.shop.formspec.owner(pos))
		else
			minetest.show_formspec(clicker:get_player_name(),"protector:shop_formspec",default.shop.formspec.customer(pos))
		end
	end,
	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		local meta = minetest.env:get_meta(pos)
		if player:get_player_name() ~= meta:get_string("owner") and minetest.is_protected(pos,player:get_player_name()) then return 0 end
		return count
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		local meta = minetest.env:get_meta(pos)
		if player:get_player_name() ~= meta:get_string("owner") and minetest.is_protected(pos,player:get_player_name())  then return 0 end
		return stack:get_count()
	end,
	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		local meta = minetest.env:get_meta(pos)
		if player:get_player_name() ~= meta:get_string("owner") and minetest.is_protected(pos,player:get_player_name())  then return 0 end
		return stack:get_count()
	end,
	can_dig = function(pos, player)
		local meta = minetest.env:get_meta(pos)
		local inv = meta:get_inventory()
		return inv:is_empty("stock") and inv:is_empty("customers_gave") and inv:is_empty("owner_wants") and inv:is_empty("owner_gives")
	end
})

minetest.register_on_player_receive_fields(function(sender, formname, fields)
	if formname == "protector:shop_formspec" and fields.exchange ~= nil and fields.exchange ~= "" then
		local name = sender:get_player_name()
		local pos = default.shop.current_shop[name]
		local meta = minetest.env:get_meta(pos)
		if meta:get_string("owner") == name and not minetest.is_protected(pos,name)  then
			minetest.chat_send_player(name,"This is your own shop, you can't exchange to yourself !")
		else
			local minv = meta:get_inventory()
			local pinv = sender:get_inventory()
			local invlist_tostring = function(invlist)
				local out = {}
				for i, item in pairs(invlist) do
					out[i] = item:to_string()
				end
				return out
			end
			local wants = minv:get_list("owner_wants")
			local gives = minv:get_list("owner_gives")
			if wants == nil or gives == nil then return end -- do not crash the server
			-- Check if we can exchange
			local can_exchange = true
			local owners_fault = false
			for i, item in pairs(wants) do
				if not pinv:contains_item("customer_gives",item) then
					can_exchange = false
				end
			end
			for i, item in pairs(gives) do
				if not minv:contains_item("stock",item) then
					can_exchange = false
					owners_fault = true
				end
			end
			if can_exchange then
				for i, item in pairs(wants) do
					pinv:remove_item("customer_gives",item)
					minv:add_item("customers_gave",item)
				end
				for i, item in pairs(gives) do
					minv:remove_item("stock",item)
					pinv:add_item("customer_gets",item)
				end
				minetest.chat_send_player(name,"Exchanged!")
			else
				if owners_fault then
					minetest.chat_send_player(name,"Exchange can not be done, contact the shop owner.")
				else
					minetest.chat_send_player(name,"Exchange can not be done, check if you put all items !")
				end
			end
		end
	end
end)

