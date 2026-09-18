model SEIR_City_Flu

global {
	
    file shape_file_buildings <- file("../includes/buildings.shp");
    file shape_file_roads <- file("../includes/roads.shp");
    
   
    geometry shape <- envelope(shape_file_buildings);
    graph road_network;
    building the_school;  
    building isolation_building;
    
    
    
    
  
    float step <- 10 #mn;
    float base_transmission_prob <- 0.33;
    float vax_transmission_prob <- 0.11;
    float recovery_prob_daily <- 0.10; 
    
    float vax_rate <- 0.0005;
   
    int initial_infected <- 20; 
    
  
    init {
        create road from: shape_file_roads;
        
        road_network <- as_edge_graph(road);
        
        create building from: shape_file_buildings;
        
      
        the_school <- building with_max_of (each.shape.area);
        the_school.is_school <- true;
        the_school.color <- #blue;    
           
        isolation_building <- (building where (each != the_school)) with_max_of (each.shape.area);
        isolation_building.color <- #orange; 
        
       
        ask building where (each != the_school and each !=isolation_building) {
            int family_size <- rnd(3, 6);
            int num_children <- rnd(0, 2);
            int num_adults <- family_size - num_children;            
            
          
            create person number: num_children {
                home <- myself;
                location <- any_location_in(home);
                destination <- the_school;
                is_child <- true;
            }            
           
            create person number: num_adults {
                home <- myself;
                location <- any_location_in(home);
                destination <- one_of(building where (each != home and each != the_school and each != isolation_building));
                is_child <- false;
            }
        }        
        
      
        ask initial_infected among person {
            disease_state <- "I";
            color <- #red;
        }
    }    

    reflex daily_interventions when: current_date.hour = 0 {
      
        int num_to_test <- int(length(person) * 1);
        ask num_to_test among person {
            if (disease_state = "I") {
                is_isolated <- true;
                isolation_timer <- 12 * 144; // 12 days in hours
            }
        }        
     
        list<person> unvax_pool <- person where (!each.is_vaccinated);
        int num_to_vax <- int(length(person) * vax_rate);
        ask num_to_vax among unvax_pool {
            is_vaccinated <- true;
        }
    }
}


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
    building home;
    building destination;
    bool is_child;
    
    string disease_state <- "S"; 
    bool is_vaccinated <- false;
    bool is_isolated <- false;
    int isolation_timer <- 0;
    int disease_timer <- 0;
    
    rgb color <- #green;  
    
    reflex commute_morning when: current_date.hour = 8 and !is_isolated {
        do goto (target: any_location_in(destination), on: road_network);
    }
    
    reflex commute_evening when: current_date.hour = 17 and !is_isolated {
        do goto (target: any_location_in(home), on: road_network);
    } 
    
    reflex go_to_isolation_building when: is_isolated {
        if (location distance_to (any_location_in(isolation_building)) > 0.5#m) {
            do goto (target: any_location_in(isolation_building), on: road_network);
        }}  
    
    reflex spread_disease when: disease_state = "I" {
        ask person at_distance 10#m where (each.disease_state = "S") {
            float infection_chance <- self.is_vaccinated ? vax_transmission_prob : base_transmission_prob;
            
            if (flip(infection_chance)) {
                self.disease_state <- "E";
                self.color <- #yellow;
                self.disease_timer <- rnd(1, 4) * 144; 
            }
        }
    }
    
    reflex disease_progression {

        if (disease_state = "E") {
            disease_timer <- disease_timer - 1;
            if (disease_timer <= 0) {
                disease_state <- "I";
                color <- #red;
                disease_timer <- 10 * 144;
            }
        } 
        if (disease_state = "I") {
            disease_timer <- disease_timer - 1;
            if (disease_timer <= 0 and disease_state != "R") {
                disease_state <- "R";
                color <- #blue;
            }
        }       
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


experiment FluSimulation type: gui {
 
    parameter "Initial Infected Count" var: initial_infected category: "Initialization" min: 1;
    parameter "Initial Vax" var: vax_rate category: "Initialization" min: 0.0005 max: 0.1;

    output {

        monitor "Total Number of Agents" value: length(person);
        monitor "Number Isolated" value: person count (each.is_isolated);
        monitor "Number Vaccinated" value: person count (each.is_vaccinated);
        monitor "Infection Rate (I)" value: (length(person) > 0) ? (float(person count (each.disease_state = "I")) / length(person)) : 0.0;
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