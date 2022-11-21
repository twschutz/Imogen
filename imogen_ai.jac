import {*} with "./faq.jac";

// Define the cai, dialogue root and state nodes
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
    }
    can nlg {
        visitor.response = "Sorry I can't handle that just yet. Anything else I can help you with?";
    }
}

// Define each state
node image_search_state:dialogue_state {
    has name = "image_search";
    can nlu {
        if (!visitor.wlk_ctx["intent"]): ::classify_intent;
        ::extract_entities;
    }
    can process {
        // Check entity transition
        if (true) {
            visitor.wlk_ctx["next_state"] = -->[0];
            visitor.wlk_ctx["prev_state"] = here;
        }
        #required_entities = -[entity_transition]->.edge[0].context["entities"];
        #if (vector.sort_by_key(visitor.wlk_ctx["entities"].d::keys) == vector.sort_by_key(required_entities)) {
        #    visitor.wlk_ctx["next_state"] = -[entity_transition]->[0];
        #    visitor.wlk_ctx["prev_state"] = here;
        #} 
        else {
            visitor.wlk_ctx["respond"] = true;
        }
    }
    can nlg {
        visitor.response = "Please tell me what you are looking for in your image. The more detail you provide, the better!\n>";
    }
}

node few_entities_state:dialogue_state {
    has name ="few_entities";
    can nlg{
        visitor.response = "We were only able to detect " + len(visitor.wlk_ctx["entities"]) + " entities in your seach. Would you like to try a more detailed search?";
    }
}

node search_cancel_state:dialogue_state {
    has name ="search_cancel";
    can nlg {
        visitor.response = "I hope I was able to find your image! I look forward to hearing from you again soon!";
    }
}

node search_confirmed_state:dialogue_state {
    has name ="search_confirmed";
    can nlg {
        visitor.response = "I will now search for your image, please hang tight!";
    }
}

node confirm_search_state:dialogue_state {
    has name ="confirm_search";
    can nlu {
        if (!visitor.wlk_ctx["intent"]): ::classify_intent;
    }
    can process {
        if (visitor.wlk_ctx["prev_state"]): visitor.wlk_ctx["respond"] = true;
        else {
            visitor.wlk_ctx["next_state"] = -[intent_transition(intent==visitor.wlk_ctx["intent"])]->[0];
            visitor.wlk_ctx["prev_state"] = here;
        }
    }
    can nlg {
        visitor.response = "Can you confirm your entities to be ... ?\n>";
    }
}

// Define transitions
edge intent_transition {
    has intent;
}
edge entity_transition {
    has entities;
}

// Static Dialouge Graph Definition
graph imogen_ai {
    has anchor dialogue_root;
    spawn {
        dialogue_root = spawn node::dialogue_root;
        image_search_state = spawn node::image_search_state;
        search_cancel_state = spawn node::search_cancel_state;
        confirm_search_state = spawn node::confirm_search_state;
        search_confirmed_state = spawn node::search_confirmed_state;
        #few_entities_state = spawn node::few_entities_state;

        dialogue_root -[intent_transition(intent="image search")]-> image_search_state;
        #image_search_state -[intent_transition(intent="cancel")]-> search_cancel_state;
        #image_search_state -[intent_transition()]-> few_entities_state;
        #few_entities_state -[intent_transition(intent="yes")]-> image_search_state;
        #few_entities_state -[intent_transition(intent="no")]-> confirm_search_state;
        image_search_state -[entity_transition(entities=[])]-> confirm_search_state;
        #image_search_state -[intent_transition(intent="provide name")]-> image_search_state;
        confirm_search_state -[intent_transition(intent="cancel")]-> search_cancel_state;
        confirm_search_state -[intent_transition(intent="yes")]-> search_confirmed_state;
        confirm_search_state -[intent_transition(intent="no")]-> image_search_state;

        #faq_root = spawn node::faq_root;
        #dialogue_root -[intent_transition(intent="I have a question")]-> faq_root;
    }
}

// Define init walker to initialize the graph
walker init {
    root {
        spawn here --> graph::imogen_ai;
        spawn here walker::talk;
    }
}

// Define walker to talk to Imogen
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