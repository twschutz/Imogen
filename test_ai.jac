# Define the parent conversational AI node
# which defines the standard abilities that all
# nodes will have in our program (nlu, process, nlg)
node cai_state {
    has name;
    can init_wlk_ctx {
        new_wlk_ctx = {
            "intent": null,
            "entities": {},
            "prev_state": null,
            "next_state": null,
            "respond": false
        };
        if ("entities" in visitor.wlk_ctx) {
            // Carry over extracted entities from previous interaction
            new_wlk_ctx["entities"] = visitor.wlk_ctx["entities"];
        }
        visitor.wlk_ctx = new_wlk_ctx;
    }
    can nlu {}
    can process {
        if (visitor.wlk_ctx["prev_state"]): visitor.wlk_ctx["respond"] = true;
        else {
            visitor.wlk_ctx["next_state"] = net.root();
            visitor.wlk_ctx["prev_state"] = here;
        }
    }
    can nlg {}
}

# Define the general dialogue state which inherits
# abilities from the parent CAI state and defines
# new abilities to perform entity and intent transitions
node dialogue_state:cai_state {
    can bi_enc.infer;
    can tfm_ner.extract_entity;

    can classify_intent {
        intent_labels = -[intent_transition]->.edge.intent;
        visitor.wlk_ctx["intent"] = bi_enc.infer(
            contexts = [visitor.question],
            candidates = intent_labels,
            context_type = "text",
            candidate_type = "text"
        )[0]["predicted"]["label"];
    }

    #can extract_entities {
    #    res = tfm_ner.extract_entity(visitor.question);
    #    for ent in res {
    #        ent_type = ent["entity_value"];
    #        ent_text = ent["entity_text"];
    #        if (!(ent_type in visitor.wlk_ctx["entities"])){
    #            visitor.wlk_ctx["entities"][ent_type] = [];
    #        }
    #        visitor.wlk_ctx["entities"][ent_type].l::append(ent_text);
    #    }
    #}
}

# Define the root of the dialouge which will serve as 
# a starting point for our graph, classifying the user's
# intiial intent
node dialogue_root:dialogue_state {
    has name = "dialogue_root";
    can nlu {
        ::classify_intent;
    }
    can process {
        visitor.wlk_ctx["next_state"] = (-[intent_transition(intent==visitor.wlk_ctx["intent"])]->)[0];
    }
    can nlg {
        visitor.response = "Sorry I can't handle that just yet. Anything else I can help you with?";
    }
}

# Define the transitions that allow walkers to move between nodes
edge intent_transition {
    has intent;
}
edge entity_transition {
    has entities;
}

# Define the image search state, a state that will handle
# high-level user inputs to the program and serve as a
# user's first interaction with Imogen
node image_search_state:dialogue_state {
    has name="image_search";
    # If the walker has no intent, classify the intent and 
    # extract any entities
    can nlu {
        if (!visitor.wlk_ctx["intent"]): ::classify_intent;
        #::extract_entities;
    }
    can process {
        # If there are entities, move to the next state.
        # Otherwise, prompt the user for their high-level search
        if (visitor.wlk_ctx["entities"]) {
            visitor.wlk_ctx["next_state"] = -[entity_transition]->[0];
            visitor.wlk_ctx["prev_state"] = here;
        } 
        else {
            # Set the walker to respond using nlg
            visitor.wlk_ctx["response"]=true;
        }
    }
    can nlg {
        if (visitor.wlk_ctx["entities"]) {
            current_entities = visitor.wlk_ctx["entities"];
            visitor.response = "To help me find your image, please enter more than two (2) entities I can search for!\n Current found entities: " + current_entities + ".\n";
        }
        else {
            visitor.response = "Please tell me what you are looking for in your image - the more detail the better!";
        }
    }
}

# Define the dialouge graph that will handle all transitions
# from one state to the next
graph imogen_ai {
    has anchor dialogue_root;
    spawn {
        dialogue_root = spawn node::dialogue_root;
        image_search_state = spawn node::image_search_state;

        dialogue_root -[intent_transition(intent="image search")]-> image_search_state;
    }
}

# Define the initialization walker which acts like the main
# function in a JAC
walker init {
    root {
        # Spawn the dialogue graph
        spawn here --> graph::imogen_ai;
        # Spawn the walker that allows conversation
        spawn here walker::talk;
    }
}

# Define the walker which allows the user to talk to Imogen
# by asking questions or specifying their search criteria
walker talk {
    has question;
    has wlk_ctx = {};
    has response;
    root {
        take --> node::dialogue_root;
    }
    cai_state {
        if (!question) {
            question = std.input("Hi, I'm Imogen - your personal image searching assistant! Would you like to search for an image? If you have any questions, I can answer those too!\n>");
            here::init_wlk_ctx;
        }
        here::nlu;
        here::process;
        if (visitor.wlk_ctx["respond"]) {
            here::nlg;
            std.out(response);
            question = null;
            take here;
        } else {
            take visitor.wlk_ctx["next_state"] else: take here;
        }
    }
}


