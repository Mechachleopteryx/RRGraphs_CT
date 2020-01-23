
include("world_path_util.jl")


# *********
# decisions
# *********


#"Quality of a link `link` to location `loc`. Calls `quality(::Infolocation,...)`."
#function quality(link :: InfoLink, loc :: InfoLocation, par)
#	# [0:3]					     [0:1.5], [0:15]	
#	quality(loc, par) / (1.0 + friction(link)*par.qual_weight_frict)
#end


"Quality of location `loc` for global planning (no effect of x)."
function quality(loc :: InfoLocation, par)
	# [0:1]
	discounted(loc.quality) + 
		# [0:1]
		discounted(loc.resources) * par.qual_weight_res
end

function costs_quality(loc :: InfoLocation, par)
	(1.0 / par.path_penalty_loc + 2.0) / 
		(1.0 / par.path_penalty_loc + quality(loc, par))
end

disc_friction(link) = 2 * link.friction.value - discounted(link.friction)

function costs_quality(link :: InfoLink, loc :: InfoLocation, par)
	disc_friction(link) * costs_quality(loc, par)
end

"Movement costs from `l1` to `l2`, taking into account `l2`'s quality."
function costs_quality(l1::InfoLocation, l2::InfoLocation, par)
	link = find_link(l1, l2)
	costs_quality(link, l2, par)
end

"Quality when looking for local improvement."
function local_quality(loc :: InfoLocation, par)
	par.qual_weight_x * loc.pos.x + quality(loc, par)
end


function make_plan!(agent, par)
	# no plan if we don't know any targets
	agent.plan, count =
		if agent.info_target == []
			[], 0
		else
			Pathfinding.path_Astar(info_current(agent), agent.info_target, 
				(l1, l2)->costs_quality(l1, l2, par), path_costs_estimate, each_neighbour)
		end
end



# ***********
# exploration
# ***********


# connect loc and link (if not already connected)
function connect!(loc :: InfoLocation, link :: InfoLink)
	# add location to link
	if link.l1 != loc && link.l2 != loc
		# link not connected yet, should have free slot
		if !known(link.l1)
			link.l1 = loc
		elseif !known(link.l2)
			link.l2 = loc
		else
			error("Error: Trying to connect a fully connected link!")
		end
	end

	# add link to location
	if ! (link in loc.links)
		add_link!(loc, link)
	end
end


# add new location to agent (based on world info)
# connect to existing links
function discover!(agent, loc :: Location, par)
	# agents start off with expected values
	inf = InfoLocation(loc.pos, loc.id, TrustedF(par.res_exp), TrustedF(par.qual_exp), [])
	# add location info to agent
	add_info!(agent, inf, loc.typ)
	# connect existing link infos
	for link in loc.links
		info_link = info(agent, link)

		# links to exit are always known
		if !known(info_link)
			if loc.typ != EXIT
				lo = otherside(link, loc)
				if lo.typ == EXIT && knows(agent, lo)
					discover!(agent, link, loc, par)
				end
			end
		# connect known links
		else				
			connect!(inf, info_link)
		end
	end

	inf	
end	


# add new link to agent (based on world info)
# connect to existing location
function discover!(agent, link :: Link, from :: Location, par)
	info_from = info(agent, from)
	@assert known(info_from)
	info_to = info(agent, otherside(link, from))
	frict = link.distance * par.frict_exp[Int(link.typ)]
	@assert frict > 0
	info_link = InfoLink(link.id, info_from, info_to, TrustedF(frict))
	add_info!(agent, info_link)
	# TODO lots of redundancy, possibly join/extend
	connect!(info_from, info_link)
	if known(info_to)
		connect!(info_to, info_link)
	end

	info_link	
end


#function current_quality(loc :: Location, par)  
#	(loc.quality + loc.traffic * par.weight_traffic) / (1.0 + loc.traffic * par.weight_traffic)
#end

function explore_at!(agent, world, loc :: Location, speed, allow_indirect, par)
	# knowledge
	inf = info(agent, loc)
	
	if !known(inf)
		inf = discover!(agent, loc, par)
	end

	# gain information on local properties
	# stochasticity?
	inf.resources = update(inf.resources, loc.resources, speed)
	inf.quality = update(inf.quality, loc.quality, speed)
	#inf.quality = update(inf.quality, current_quality(loc, par), speed)

	# only location, no links, done
	if ! allow_indirect
		return inf, loc
	end

	# gain info on links and linked locations
	
	for link in loc.links
		info_link = info(agent, link)

		if !known(info_link) && rand() < par.p_find_links
			info_link = discover!(agent, link, loc, par)

			#info_link.friction = TrustedF(link.friction, par.trust_found_links)
			info_link.friction = update(info_link.friction, link.friction, speed)
			
			# no info, but position is known
			explore_at!(agent, world, otherside(link, loc), 0.0, false, par)
		end

		# we might get info on connected location
		if known(info_link) && rand() < par.p_find_dests
			explore_at!(agent, world, otherside(link, loc), 0.5 * speed, false, par)
		end
	end

	inf, loc
end


function explore_at!(agent, world, from :: Location, link :: Link, speed, par)
	# knowledge
	inf = info(agent, link)

	if !known(inf)
		inf = discover!(agent, from, link, par)
	end

	# gain information on local properties
	inf.friction = update(inf.friction, link.friction, speed)

	inf, link
end

# ********************
# information exchange
# ********************


struct InfoPars
	convince :: Float64
	convert :: Float64
	confuse :: Float64
	error :: Float64
end


function receive_belief(self::TrustedF, other::TrustedF, par)
	ci = par.convince
	ce = par.convert 
	cu = par.confuse

	t = self.trust		# trust
	d = 1.0 - t		# doubt
	v = self.value

	# perceived values after error
	t_pcv = limit(0.000001, other.trust + unf_delta(par.error), 0.99999)
	d_pcv = 1.0 - t_pcv
	v_pcv = max(0.0, other.value + unf_delta(par.error))
	
	dist_pcv = abs(v-v_pcv) / (v + v_pcv + 0.00001)

	# sum up values according to area of overlap between 1 and 2
	# from point of view of 1:
	# doubt x doubt -> doubt
	# trust x doubt -> trust
	# doubt x trust -> doubt / convince
	# trust x trust -> trust / convert / confuse (doubt)

	#					doubt x doubt		doubt x trust
	d_ = 					d * d_pcv + 	d * t_pcv * (1.0 - ci) + 
	#	trust x trust
		t * t_pcv * cu * dist_pcv
	#	trust x doubt
	v_ = t * d_pcv * v + 					d * t_pcv * ci * v_pcv + 
		t * t_pcv * (1.0 - cu * dist_pcv) * ((1.0 - ce) * v + ce * v_pcv)

	limit(0.000001, d_, 0.99999), v_
end

function exchange_beliefs(val1::TrustedF, val2::TrustedF, par1, par2)
	if val1.trust == 0.0 && val2.trust == 0.0
		return val1, val2
	end

	d1_, v1_ = receive_belief(val1, val2, par1)

	d2_, v2_ = receive_belief(val2, val1, par2)

	TrustedF(v1_ / (1.0-d1_), 1.0 - d1_), TrustedF(v2_ / (1.0-d2_), 1.0 - d2_)
end


function exchange_loc_info(loc, info1, info2, a1, a2, p1, p2, par)
	# neither agent knows anything
	if !known(info1) && !known(info2)
		return	
	end
	
	if !known(info1)
		info1 = discover!(a1, loc, par)
	elseif !known(info2) && !arrived(a2)
		info2 = discover!(a2, loc, par)
	end

	# both have knowledge at l, compare by trust and transfer accordingly
	if known(info1) && known(info2)
		res1, res2 = exchange_beliefs(info1.resources, info2.resources, p1, p2)
		qual1, qual2 = exchange_beliefs(info1.quality, info2.quality, p1, p2)
		info1.resources = res1
		info1.quality = qual1
		# only a2 can have arrived
		if !arrived(a2) 
			info2.resources = res2
			info2.quality = qual2
		end
	end
end


function exchange_link_info(link, info1, info2, a1, a2, p1, p2, par)
	# neither agent knows anything
	if !known(info1) && !known(info2)
		return
	end

	# only one agent knows the link
	if !known(info1)
		if knows(a1, link.l1) && knows(a1, link.l2)
			info1 = discover!(a1, link, link.l1, par)
		end
	elseif !known(info2) && !arrived(a2)
		if knows(a2, link.l1) && knows(a2, link.l2)
			info2 = discover!(a2, link, link.l1, par)
		end
	end
	
	# both have knowledge at l, compare by trust and transfer accordingly
	if known(info1) && known(info2)
		frict1, frict2 = exchange_beliefs(info1.friction, info2.friction, p1, p2)
		info1.friction = frict1
		if !arrived(a2)
			info2.friction = frict2
		end
	end
end


function exchange_info!(a1::Agent, a2::Agent, world::World, par)
	p2 = InfoPars(par.convince, par.convert, par.confuse, par.error)
	# values a1 experiences, have to be adjusted if a2 has already arrived
	p1 = if arrived(a2)
			InfoPars(par.convince^(1.0/par.weight_arr), par.convert^(1.0/par.weight_arr), par.confuse,
				par.error)
		else
			p2
		end

	for l in eachindex(a1.info_loc)
		if rand() > par.p_transfer_info
			continue
		end
		exchange_loc_info(world.cities[l], a1.info_loc[l], a2.info_loc[l], a1, a2, p1, p2, par)
	end

	for l in eachindex(a1.info_link)
		if rand() > par.p_transfer_info
			continue
		end
		exchange_link_info(world.links[l], a1.info_link[l], a2.info_link[l], a1, a2, p1, p2, par)
	end

	a1.out_of_date += 1
	if ! arrived(a2)
		a2.out_of_date += 1
	end
end



# ********
# contacts
# ********


# TODO NOT USED
#function  step_agent_contacts!(agent, par)
#	for i in length(agent.contacts):-1:1
#		if rand() < par.p_drop_contact
#			drop_at!(agent.contacts, i)
#		end
#	end
#end

maxed(agent, par) = length(agent.contacts) >= par.n_contacts_max

# *********************
# event functions/rates
# *********************

function move_rate(agent, par)
	loc = info_current(agent)

	if agent.capital < par.save_thresh && income(agent.loc, par) > par.save_income
		return 0.0
	end

	# we've made a decision and we've got enough money, let's go
	1.0
end


# same as ML3
rate_transit(agent, par) = par.move_speed / agent.link.friction

rate_contacts(agent, par) = (length(agent.loc.people)-1) * par.p_keep_contact

rate_talk(agent, par) = length(agent.contacts) * par.p_info_contacts

rate_plan(agent, par) = agent.out_of_date * par.rate_plan


income(loc, par) = par.ben_resources * loc.resources - par.costs_stay

function costs_stay!(agent, par)
	agent.capital += income(agent.loc, par)
	[agent]
end


function plan_costs!(agent, par)
	make_plan!(agent, par)

	agent.out_of_date = 1.0

	if agent.plan != []
		agent.planned += 1
		return [agent]
	end

	# *** empty plan
	
	loc = info_current(agent)

	if length(loc.links) == 0
		return [agent]
	end

	quals = Float64[]
	sizehint!(quals, length(loc.links)+1)
	prev = 0.0

	for l in loc.links
		other = otherside(l, loc)
		q = local_quality(other, par) * par.qual_tol_frict / (par.qual_tol_frict + disc_friction(l))
		push!(quals, q + prev)
		prev = quals[end]
	end

	# add current location, might be best option
	q = local_quality(loc, par)
	push!(quals, q + prev)

	best = 0
	if quals[end] > 0.0
		r = rand() * (quals[end] - 0.000001)
		best = findfirst(x -> x>r, quals)
	end

	if best < length(quals)
		# go to best neighbouring location 
		agent.plan = [otherside(loc.links[best], loc)]
	end

	[agent]
end


# explore while staying at a location
function explore_stay!(agent, world, par)
	explore_at!(agent, world, agent.loc, par.speed_expl_stay, true, par)

	agent.out_of_date += 0.5

	[agent]
end

function meet_locally!(agent, world, par)
	@assert ! arrived(agent)
	pop = agent.loc.people

	# with rescheduling this should not happen
	@assert length(pop) > 1

	while (a = rand(pop)) == agent end

	add_contact!(agent, a)
	if !maxed(a, par)
		add_contact!(a, agent)
	end

	exchange_info!(agent, a, world, par)

	[agent, a]
end


function talk_once!(agent, world, par)
	@assert ! arrived(agent)
	other = rand(agent.contacts)

	exchange_info!(agent, other, world, par)

	(arrived(other) ? [agent] : [agent, other])
end


function costs_move!(agent, link :: Link, par)
	agent.capital -= par.costs_move * link.friction

	[agent]
end


function start_move!(agent, world, par)
	@assert ! arrived(agent)

	next = info2real(agent.plan[end], world)
	link = find_link(agent.loc, next)

	set_transit!(agent, link)
	
	# update traffic counter
	link.count += 1
	agent.steps += 1

	costs_move!(agent, link, par)
	remove_agent!(world, agent)

	# link exploration is a consequence of direct experience, so
	# it always happens
	explore_at!(agent, world, agent.loc, link, par.speed_expl_move, par)

	[agent; agent.loc.people]
end


function finish_move!(agent, world, par)
	next = info2real(agent.plan[end], world)
	pop!(agent.plan)

	add_agent!(next, agent)
	end_transit!(agent, next)

	if arrived(agent)
		return []
	end

	next.people
end




# **********
# deprecated
# **********


#function costs_quality(plan :: Vector{InfoLocation}, par)
#	c = 0.0
#	for i in 1:length(plan)-1
#		# plan is sorted in reverse (target sits at 1)
#		c += costs_quality(plan[i+1], plan[i], par)
#	end
#	c
#end


# TODO properties of waystations
#"Quality of a plan consisting of a sequence of locations."
#function quality(plan :: Vector{InfoLocation}, par)
#	if length(plan) == 2
#		return quality(find_link(plan[2], plan[1]), plan[1], par)
#	end
#
#	# start out with quality of target
#	q = quality(plan[1],  par)
#
#	f = 0.0
#	for i in 1:length(plan)-1
#		f += find_link(plan[i], plan[i+1]).friction.value
#	end
#
#	q / (1.0 + f * par.qual_weight_frict)
#end




#function plan_old!(agent, par)
#	make_plan!(agent, par)
#
#	loc = info_current(agent)
#
#	quals = fill(0.0, length(loc.links)+1)
#	quals[1] = quality(loc, par)
#
#	for i in eachindex(loc.links)
#		q = quality(loc.links[i], otherside(loc.links[i], loc), par)
#		@assert !isnan(q)
#		quals[i+1] = quals[i] + q
#	end
#
#	# plan goes into the choice as well
#	if agent.plan != []
#		push!(quals, quality(agent.plan, par) + quals[end])
#	end
#
#	best = 0
#	if quals[end] > 0
#		r = rand() * (quals[end] - 0.0001)
#		# -1 because first el is stay
#		best = findfirst(x -> x>r, quals) - 1
#	end
#
#	if best == length(quals) - 1 && agent.plan != []
#		agent.planned += 1
#	end
#
#	# either stay or use planned path
#	if best == 0 ||
#		(best == length(quals) - 1 && agent.plan != [])
#		return agent
#	end
#
#	# go to best neighbouring location 
#	agent.plan = [otherside(loc.links[best], loc), loc]
#
#	agent
#end


#function plan_simple!(agent, par)
#	loc = info_current(agent)
#
#	quals = fill(0.0, length(loc.links))
#
#	for i in eachindex(loc.links)
#		q = quality(loc.links[i], otherside(loc.links[i], loc), par)
#		@assert !isnan(q)
#		quals[i] = q + (i > 1 ? quals[i-1] : 0.0)
#	end
#
#	if quals[end] > 0
#		r = rand() * (quals[end] - 0.0001)
#		# -1 because first el is stay
#		best = findfirst(x -> x>r, quals)
#	end
#
#	agent.next = otherside(loc.links[best], loc)
#end


#function decide_move(agent::Agent, world::World, par)
	# end is current location
#	info2real(agent.plan[end-1])
#end
