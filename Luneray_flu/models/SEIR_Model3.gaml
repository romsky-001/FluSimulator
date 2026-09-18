model SEIR_City_Flu

global {
    file shape_file_buildings <- file("../includes/buildings.shp");
    file shape_file_roads <- file("../includes/roads.shp");
    
    // --- Environment & Routing ---
    geometry shape <- envelope(shape_file_buildings);
    graph road_network;
    building the_school;  
    building isolation_building; // Quarantine facility
    list<building> workplaces;   // NEW: List to hold the 4 big workplace buildings
    
    // --- Model Parameters ---
    float step <- 10 #mn;
    float base_transmission_prob <- 0.33;
    float vax_transmission_prob <- 0.11;
    float recovery_prob_daily <- 0.10; 
    int initial_infected <- 20; 
    float vax_rate <- 0.01;
    float testing_rate <- 0.01;
    
    // --- Initialization ---
    init {
        create road from: shape_file_roads;
        road_network <- as_edge_graph(road);
        
        create building from: shape_file_buildings;
        
        // 1. Find the school (largest building)
        the_school <- building with_max_of (each.shape.area);
        the_school.is_school <- true;
        the_school.color <- #blue;        
        
        // 2. Find the isolation building (largest remaining building after the school)
        isolation_building <- (building where (each != the_school)) with_max_of (each.shape.area);
        isolation_building.color <- #orange; 
        
        // 3. NEW: Find the 4 largest buildings (excluding school and isolation building) to be workplaces
        list<building> available_buildings <- building where (each != the_school and each != isolation_building);
        workplaces <- [];
        loop i from: 0 to: 50	 {
            if (length(available_buildings) > 0) {
                building big_workplace <- available_buildings with_max_of (each.shape.area);
                add big_workplace to: workplaces;
                big_workplace.color <- #purple; // Highlight workplaces in purple
                available_buildings <- available_buildings - big_workplace;
            }
        }
        
        // 4. Initialize families in residential buildings (excluding school, isolation, and workplaces)
        ask building where (each != the_school and each != isolation_building and !(workplaces contains each)) {
            int family_size <- rnd(3, 6);
            int num_children <- rnd(0, 2);
            int num_adults <- family_size - num_children;            
            
            // Create children
            create person number: num_children {
                home <- myself;
                location <- any_location_in(home);
                destination <- the_school;
                is_child <- true;
            }            
            // Create adults (assigned to one of the 4 big workplaces)
            create person number: num_adults {
                home <- myself;
                location <- any_location_in(home);
                destination <- one_of(workplaces);
                is_child <- false;
            }
        }        
        
        // Infect people based on the parameter to start the epidemic
        ask initial_infected among person {
            disease_state <- "I";
            color <- #red;
        }
    }    
    
    // --- Daily Interventions (Triggered at Midnight) ---
    reflex daily_interventions when: current_date.hour = 0 {
        // 1. Testing (1% of population)
        int num_to_test <- int(length(person) * testing_rate);
        ask num_to_test among person {
            if (disease_state = "I") {
                is_isolated <- true;
                isolation_timer <- 12 * 144;
            }
        }        
        // 2. Vaccination (0.05% of unvax population)
        list<person> unvax_pool <- person where (!each.is_vaccinated);
        int num_to_vax <- int(length(person) * vax_rate);
        ask num_to_vax among unvax_pool {
            is_vaccinated <- true;
        }
    }
}

// --- Species Definitions ---
species building {
    bool is_school <- false;
    rgb color <- #gray;
    aspect base {
        draw shape color: color border: #black;
    }
}

species road {
    rgb color <- #darkgray;
    aspect base {
        draw shape color: color;
    }
}

species person skills: [moving] {
    // Attributes
    building home;
    building destination;
    bool is_child;
    
    // Health variables
    string disease_state <- "S"; 
    bool is_vaccinated <- false;
    bool is_isolated <- false;
    int isolation_timer <- 0;
    int disease_timer <- 0;
    
    rgb color <- #green;  
    
    // --- Mobility Reflexes ---
    reflex commute_morning when: current_date.hour = 8 and !is_isolated {
        do goto (target: any_location_in(destination), on: road_network);
    }
    
    reflex commute_evening when: current_date.hour = 17 and !is_isolated {
        do goto (target: any_location_in(home), on: road_network);
    }    

    // Forces isolated agents to move to and stay inside the big isolation building
    reflex go_to_isolation_building when: is_isolated {
        if (location distance_to (any_location_in(isolation_building)) > 2#m) {
            do goto (target: any_location_in(isolation_building), on: road_network);
        }
    }
    
    // --- Epidemic Reflexes ---
    reflex spread_disease when: disease_state = "I" {
        ask person at_distance 10#m where (each.disease_state = "S") {
            float infection_chance <- self.is_vaccinated ? vax_transmission_prob : base_transmission_prob;
            
            if (flip(infection_chance)) {
                self.disease_state <- "E";
                self.color <- #yellow;
                self.disease_timer <- rnd(1, 4) * 144; // 1-4 days incubation
            }
        }
    }
    
    reflex disease_progression {
        // Handle incubation
        if (disease_state = "E") {
            disease_timer <- disease_timer - 1;
            if (disease_timer <= 0) {
                disease_state <- "I";
                color <- #red;
                disease_timer <- 10 * 144; // Max 8 days sick
            }
        } 
        // Handle sickness and recovery
        if (disease_state = "I") {
            disease_timer <- disease_timer - 1;
            if (disease_timer <= 0 and disease_state != "R") {
                disease_state <- "R";
                color <- #blue;
            }
        }       
        // Handle isolation countdown
        if (is_isolated) {
            isolation_timer <- isolation_timer - 1;
            if (isolation_timer <= 0) {
                is_isolated <- false;
            }
        }
    }
    
    aspect base {
        draw circle(3#m) color: color border: #black;
    }
}

// --- GUI Display ---
experiment FluSimulation type: gui {
    
    parameter "Initial Infected Count" var: initial_infected category: "Initialization" min: 1;
    parameter "Vaccination Rate" var: vax_rate category: "Initialization" min: 0.01;
    parameter "Testing_Rate" var: testing_rate category: "Initialization" min: 0.01;
    
    output {
        monitor "Total Number of person" value: length(person);
        monitor "Number Isolated" value: person count (each.is_isolated);
        monitor "Number Vaccinated" value: person count (each.is_vaccinated);
        monitor "Infected" value: person count (each.disease_state = "I");
        monitor "Recovered" value: person count (each.disease_state = "R");
        display map_display type: opengl {
            species road aspect: base;
            species building aspect: base;
            species person aspect: base;
        }
        
        display epidemic_curves {
            chart "SEIR Model" type: series {
                data "Susceptible" value: person count (each.disease_state = "S") color: #green;
                data "Exposed" value: person count (each.disease_state = "E") color: #yellow;
                data "Infected" value: person count (each.disease_state = "I") color: #red;
                data "Recovered" value: person count (each.disease_state = "R") color: #blue;
            }
        }
    }
}