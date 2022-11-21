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
        index="i";
        for value in visitor.wlk_ctx["entities"].d::values[0] {
            string+= "Entity [" + index + "]: " + value + "\n";
            index+="i";
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
    has response = "";
    has intent = false;
    can nlu {
        if not visitor.wlk_ctx["intent"] {
            if response == "" {
                response = visitor.question;
            }
            ::classify_intent;
        }
    }
    can process {
        if response == "" or intent == false {
            visitor.wlk_ctx["respond"] = true;
        }
        else {
            visitor.wlk_ctx["next_state"] = -[intent_transition(intent==visitor.wlk_ctx["intent"])]->[0];
            visitor.wlk_ctx["prev_state"] = here;
        }
    }
    can nlg {
        if response == "" {
            visitor.response = "What entities would you like to add?";
        }
        else {
            visitor.response = "Would you like to delete entities as well?";
            intent = true;
        }
    }
}

node delete_search_state:dialogue_state {
    has name = "delete_state";
    has response = "";
    has intent = false;
    can nlu {
        if not visitor.wlk_ctx["intent"] {
            if response == "" {
                response = visitor.question;
            }
            ::classify_intent;
        }   
    }
    can process {
        if response == "" or intent == false {
            visitor.wlk_ctx["respond"] = true;
        }
        else {
            visitor.wlk_ctx["next_state"] = -[intent_transition(intent==visitor.wlk_ctx["intent"])]->[0];
            visitor.wlk_ctx["prev_state"] = here;
        }
    }
    can nlg {
        if response == "" {
            visitor.response = "What entities would you like to delete?";
        }
        else {
            visitor.response = "Would you like to add entities as well?";
            intent = true;
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
        add_search_state -[intent_transition(intent="no")]-> confirm_search_state;
        delete_search_state -[intent_transition(intent="no")]-> confirm_search_state;
        add_search_state -[intent_transition(intent="yes")]-> delete_search_state;
        delete_search_state -[intent_transition(intent="yes")]-> add_search_state;
    }
}

walker init {
    root {
        spawn here --> graph::dialogue_system;
        spawn here walker::talk;
    }
}

walker talk {
    has question;
    has wlk_ctx = {};
    has response;
    has input;
    root {
        take --> node::dialogue_root;
    }
    dialogue_state {
        if (!question and !visitor.wlk_ctx) {
            question = std.input("Hi, I'm Imogen! Would you like to search for an image or ask questions?\n>");
            here::init_wlk_ctx;
        }
        elif(!question) {
            question = std.input(">");
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