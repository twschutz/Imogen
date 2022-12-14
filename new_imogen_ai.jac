node dialogue_state {
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

    can extract_entities {
        res = tfm_ner.extract_entity(visitor.question);
        for ent in res {
            ent_type = ent["entity_value"];
            ent_text = ent["entity_text"];
            if (!(ent_type in visitor.wlk_ctx["entities"])){
                visitor.wlk_ctx["entities"][ent_type] = [];
            }
            visitor.wlk_ctx["entities"][ent_type].l::append(ent_text);
        }
    }

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

node dialogue_root:dialogue_state {
    has name = "dialogue_root";
    can nlu {
        ::classify_intent;
    }
    can process {
        visitor.wlk_ctx["next_state"] = (-[intent_transition(intent==visitor.wlk_ctx["intent"])]->)[0];
        visitor.wlk_ctx["prev_state"] = here;
    }
    can nlg {
        visitor.response = "Sorry I can't handle that just yet. Anything else I can help you with?";
    }
}

edge intent_transition {
    has intent;
}

edge entity_transition {
    has entities;
}

node confirm_search_state:dialogue_state {
    has name = "confirm_search";
    can nlu {
        if (!visitor.wlk_ctx["intent"]): ::classify_intent;
    }
    can process {
        if (!visitor.wlk_ctx["prev_state"]) {
            visitor.wlk_ctx["next_state"] = -[intent_transition(intent==visitor.wlk_ctx["intent"])]->[0];
            visitor.wlk_ctx["prev_state"] = here;
        }
        else {
            visitor.wlk_ctx["respond"] = true;
            visitor.wlk_ctx["prev_state"] = null;
        }
    }
    can nlg {
        string = "";
        index=0;
        for category in visitor.wlk_ctx["entities"].d::keys {
            for value in visitor.wlk_ctx["entities"][category] {
                string+= "Entity [" + index.str + "]: " + value + "\n";
                index+=1;
            }
        }
        visitor.response = "Here are the entities I found...\n" + string + "Is that correct?";
    }
}

node confirmed_search_state:dialogue_state {
    has name = "confirmed_search";
    can nlg {
        visitor.response = "Thank you for confirming! Finding your images now...";
    }
}

node cancel_search_state:dialogue_state {
    has name = "cancel_search";
    can nlg {
        visitor.response = "Sorry I couldn't help, Please try again!";
    }
}

node image_search_state:dialogue_state {
    has name = "image_search";
    can nlu {
        if not visitor.wlk_ctx["intent"] {
            ::classify_intent;
            ::extract_entities;
        }
    }
    can process {
        if(!visitor.wlk_ctx["entities"]) {
            visitor.wlk_ctx["respond"] = true;
        }
        else {
            visitor.wlk_ctx["next_state"] = -[intent_transition(intent=="confirm")]->[0];
            visitor.wlk_ctx["prev_state"] = here;
        }
    }
    can nlg {
        visitor.response = "What are you searching for?";
    }
}

node modify_search_state:dialogue_state {
    has name = "modify_state";
    can nlu {
        if not visitor.wlk_ctx["intent"] {
            ::classify_intent;
        }   
    }
    can process {
        if visitor.wlk_ctx["prev_state"] {
            visitor.wlk_ctx["respond"] = true;
            visitor.wlk_ctx["prev_state"] = null;
        }
        else {
            visitor.wlk_ctx["next_state"] = -[intent_transition(intent==visitor.wlk_ctx["intent"])]->[0];
            visitor.wlk_ctx["prev_state"] = here;
        }
    }
    can nlg {
        visitor.response = "Would you like to delete or add entities to the list?";
    }
}

node add_search_state:dialogue_state {
    has name = "add_state";
    has category = "";
    has entity = "";
    can nlu {
        if not visitor.wlk_ctx["intent"] {
            if category == "" {
                category = visitor.question;
            }
            elif entity == "" {
                entity = visitor.question;
            }
            ::classify_intent;
        }
    }
    can process {
        if category == "" or entity == ""{
            visitor.wlk_ctx["respond"] = true;
        }
        else {
            if category in visitor.wlk_ctx["entities"] {
                visitor.wlk_ctx["entities"][category].l::append(entity);
            }
            else {
                 visitor.wlk_ctx["entities"][category] = [entity];
            }
            category = ""; entity = "";
            visitor.wlk_ctx["next_state"] = -[intent_transition(intent=="confirm")]->[0];
            visitor.wlk_ctx["prev_state"] = here;
        }
    }
    can nlg {
        if category == "" {
            visitor.response = "What category does your entity fall into? (name, location, object, time, month)";
        }
        elif entity == "" {
            visitor.response = "What is the name of the entity with category = " + category + " which you are adding?";
        }
    }
}

node delete_search_state:dialogue_state {
    has name = "delete_state";
    has category = "";
    has indexstr = "";
    can nlu {
        if not visitor.wlk_ctx["intent"] {
            if category == "" {
                category = visitor.question;
            }
            elif indexstr == "" {
                indexstr = visitor.question;
            }
            ::classify_intent;
        }   
    }
    can process {
        if category == "" or indexstr == "" {
            visitor.wlk_ctx["respond"] = true;
        }
        else {
            delIndex = -1;
            for i in [0,1,2,3,4,5,6,7,8,9] {
                if i.str == indexstr {
                    delIndex = i;
                    break;
                }
            }
            visitor.wlk_ctx["entities"][category].list::pop(delIndex);
            visitor.wlk_ctx["next_state"] = -[intent_transition(intent==visitor.wlk_ctx["intent"])]->[0];
            visitor.wlk_ctx["prev_state"] = here;
        }
    }
    can nlg {
        if category == "" {
            visitor.response = "What category is the entity you would like to delete? (name, location, object)";
        }
        elif indexstr == "" {
            string = "";
            index = 0;
            for value in visitor.wlk_ctx["entities"][category] {
                string+= "Entity [" + index.str + "]: " + value + "\n";
                index+=1;
            }
            visitor.response = "What is the index of the entity which you wish to delete? (0, 1, 2, ...)\n" + string;
        }
    }
}

graph dialogue_system {
    has anchor dialogue_root;
    spawn {
        dialogue_root = spawn node::dialogue_root;
        confirm_search_state = spawn node::confirm_search_state;
        confirmed_search_state = spawn node::confirmed_search_state;
        cancel_search_state = spawn node::cancel_search_state;
        image_search_state = spawn node::image_search_state;
        modify_search_state = spawn node::modify_search_state;
        add_search_state = spawn node::add_search_state;
        delete_search_state = spawn node::delete_search_state;

        dialogue_root -[intent_transition(intent="image search")]-> image_search_state;
        image_search_state -[intent_transition(intent="confirm")]-> confirm_search_state;
        confirm_search_state -[intent_transition(intent="cancel")]-> cancel_search_state;
        confirm_search_state -[intent_transition(intent="yes")]-> confirmed_search_state;
        confirm_search_state -[intent_transition(intent="no")]-> modify_search_state;
        modify_search_state -[intent_transition(intent="add")]-> add_search_state;
        modify_search_state -[intent_transition(intent="delete")]-> delete_search_state;
        add_search_state -[intent_transition(intent="confirm")]-> confirm_search_state;
        delete_search_state -[intent_transition(intent="confirm")]-> confirm_search_state;
    }
}

walker init {
    root {
        spawn here --> graph::dialogue_system;
        spawn here walker::talk;
    }
}

walker talk {
    has question, interactive = false;
    has wlk_ctx = {
        "intent": null,
        "entities": {},
        "prev_state": null,
        "next_state": null,
        "respond": false
    };
    has response;
    has input;
    root {
        take --> node::dialogue_root;
    }
    dialogue_state {
        if (!question and !visitor.wlk_ctx and interactive) {
            question = std.input("Hi, I'm Imogen! What would you like to do?\n>");
            here::init_wlk_ctx;
        }
        elif (!question and !interactive){
            std.err("ERROR: question is required for non-interactive mode");
            disengage;
        }
        elif (!question and interactive) {
            question = std.input(">");
            here::init_wlk_ctx;
        }
        here::nlu;
        here::process;
        if (visitor.wlk_ctx["respond"]) {
            here::nlg;
            if (interactive): std.out(response);
            else {
                yield report response;
                here::init_wlk_ctx;
            }
            question = null;
            take here;
        } else {
            take visitor.wlk_ctx["next_state"] else: take here;
        }
    }
}