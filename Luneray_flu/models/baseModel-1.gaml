model baseModel1

global {
	shape_file roads0_shape_file <-
    shape_file("../includes/realistic_city_roads.shp");

shape_file buildings0_shape_file <-
    shape_file("../includes/realistic_city_buildings.shp");

shape_file parks_shape_file <-
    shape_file("../includes/realistic_city_parks.shp");

shape_file water_shape_file <-
    shape_file("../includes/realistic_city_water.shp");

shape_file landmarks_shape_file <-
    shape_file("../includes/realistic_city_landmarks.shp");

shape_file boundary_shape_file <-
    shape_file("../includes/realistic_city_boundary.shp");


  

    geometry shape <- envelope(boundary_shape_file);

    float step <- 1#mn;

    int minutes_per_day <- 24 * 60;

    int infectious_period_days <- 10;

    int infectious_period <-
        infectious_period_days * minutes_per_day;

    int nb_people <- 20;

    int nb_infected_init <- 2;

    int susceptible_count <-
        nb_people - nb_infected_init
        update:
            people count (each.health_state = "S");

    int infected_count <- nb_infected_init
        update:
            people count (each.health_state = "I");

    int recovered_count <- 0
        update:
            people count (each.health_state = "R");

    float infected_rate <-
        float(nb_infected_init) / nb_people
        update:
            float(infected_count) / nb_people;

    float infection_probability <- 0.33;

    float infection_distance <- 10#m;

    graph<geometry, geometry> road_network;


    init {
		create road from: roads0_shape_file;

road_network <- as_edge_graph(road);

create building from: buildings0_shape_file;

create park from: parks_shape_file;

create water from: water_shape_file;

create landmark from: landmarks_shape_file;

        create people number: nb_people {
			my_house <- one_of(building);

            current_building <- my_house;

            if (my_house != nil) {
				location <- any_location_in(my_house);
			} else {
				location <- any_location_in(world.shape);
			}
		}

        ask nb_infected_init among people {
			health_state <- "I";

            infected_time <- 0;
		}
	}


    reflex stop_simulation
        when: cycle > 0 and infected_count = 0 {
		do pause;
	}
}


species road {
	rgb road_color <- one_of([#white, #gold, #orange, #lightgray]);

    float road_width <- rnd(2.0, 5.0);


    aspect default {
		draw shape
            color: road_color
            width: road_width;
	}
}


species building {
	rgb building_color <- one_of([#lightyellow, #orange, #steelblue, #purple, #pink, #cyan, #lightgreen]);


    aspect default {
		draw shape
            color: building_color
            border: #darkgray;
	}
}



species park {
	aspect default {
		draw shape
            color: #lightgreen
            border: #darkgreen;
	}
}


species water {
	aspect default {
		draw shape
            color: #skyblue
            border: #blue;
	}
}


species landmark {
	aspect default {
		draw circle(10 #m)
            color: #orange
            border: #white;
	}
}

species people skills: [moving] {
	string health_state <- "S";

    int infected_time <- 0;

    rgb person_color <- #yellow;

    float speed <- 30#km / #h;

    building my_house;

    building current_building;

    building destination_building;

    point target;


    reflex select_destination
        when: target = nil {
		list<building> possible_buildings <-
            building where (each != current_building);

        if (not empty(possible_buildings)) {
			destination_building <-
                one_of(possible_buildings);

            target <-
                any_location_in(
                    destination_building);
		}
	}


    reflex move_to_destination
        when: target != nil {
		do goto
         target: target
    on: road_network;

        if (
            location distance_to target < 5#m
        ) {
			current_building <-
                destination_building;

            destination_building <- nil;

            target <- nil;
		}
	}


    reflex infect_other_people
        when: health_state = "I" {
		list<people> nearby_susceptible_people <-
            people at_distance infection_distance where (each.health_state = "S");

        ask nearby_susceptible_people {
			if flip(infection_probability) {
				health_state <- "I";

                infected_time <- 0;
			}
		}
	}


    reflex recover
        when: health_state = "I" {
		infected_time <- infected_time + 1;

        if (
            infected_time >= infectious_period
        ) {
			health_state <- "R";

            infected_time <- 0;
		}
	}


    reflex update_color {
		if (health_state = "S") {
			person_color <- #yellow;
		}

        if (health_state = "I") {
			person_color <- #red;
		}

        if (health_state = "R") {
			person_color <- #green;
		}
	}


    aspect default {
		draw circle(7 #m)
            color: person_color
            border: #black;
	}
}


experiment main_experiment type: gui {
	parameter "Initial infected people"
        var: nb_infected_init
        min: 1
        max: nb_people
        step: 1;

    parameter "Infection probability"
        var: infection_probability
        min: 0.0
        max: 1.0
        step: 0.01;

    parameter "Infection distance"
        var: infection_distance
        min: 1#m
        max: 50#m
        step: 1#m;


    output {
		monitor "Simulation cycle"
            value: cycle;

        monitor "Simulated day"
            value:
                cycle div minutes_per_day;

        monitor "Total population"
            value: nb_people;

        monitor "Susceptible people"
            value: susceptible_count;

        monitor "Infected people"
            value: infected_count;

        monitor "Recovered people"
            value: recovered_count;

        monitor "Infection rate"
            value: infected_rate;

        monitor "Population verification"
            value:
                susceptible_count + infected_count + recovered_count;

        monitor "People with targets"
            value:
                people count (each.target != nil);

        monitor "People without targets"
            value:
                people count (each.target = nil);

        monitor "Road agents"
            value: length(road);

        monitor "Building agents"
            value: length(building);

        monitor "Park agents"
            value: length(park);

        monitor "Water agents"
            value: length(water);


       display city_map
    type: opengl
    background: rgb(44, 50, 58) {

    species water aspect: default;

    species park aspect: default;

    species road aspect: default;

    species building aspect: default;

    species landmark aspect: default;

    species people aspect: default;
}


        display epidemic_chart {

            chart "SIR disease spreading"
                type: series {
			data "Susceptible"
                    value: susceptible_count
                    color: #yellow;

                data "Infected"
                    value: infected_count
                    color: #red;

                data "Recovered"
                    value: recovered_count
                    color: #green;
		}
        }
	}
}