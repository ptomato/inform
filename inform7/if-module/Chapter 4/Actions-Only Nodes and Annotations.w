[ActionsNodes::] Actions-Only Nodes and Annotations.

Additional syntax tree node and annotation types used by the actions plugin.

@ There is just one additional node type, but it can take four new annotations:

@e ACTION_NT  /* "taking something closed" */

@e action_meaning_ANNOT /* |action_pattern|: meaning in parse tree when used as noun */
@e constant_action_name_ANNOT /* |action_name|: for constant values */
@e constant_action_pattern_ANNOT /* |action_pattern|: for constant values */
@e constant_explicit_action_ANNOT /* |explicit_action|: for constant values */
@e constant_named_action_pattern_ANNOT /* |named_action_pattern|: for constant values */

= (early code)
DECLARE_ANNOTATION_FUNCTIONS(action_meaning, action_pattern)
DECLARE_ANNOTATION_FUNCTIONS(constant_action_name, action_name)
DECLARE_ANNOTATION_FUNCTIONS(constant_action_pattern, action_pattern)
DECLARE_ANNOTATION_FUNCTIONS(constant_explicit_action, explicit_action)
DECLARE_ANNOTATION_FUNCTIONS(constant_named_action_pattern, named_action_pattern)

@ =
MAKE_ANNOTATION_FUNCTIONS(action_meaning, action_pattern)
MAKE_ANNOTATION_FUNCTIONS(constant_action_name, action_name)
MAKE_ANNOTATION_FUNCTIONS(constant_action_pattern, action_pattern)
MAKE_ANNOTATION_FUNCTIONS(constant_explicit_action, explicit_action)
MAKE_ANNOTATION_FUNCTIONS(constant_named_action_pattern, named_action_pattern)

void ActionsNodes::nodes_and_annotations(void) {
	NodeType::new(ACTION_NT, I"ACTION_NT", 0, INFTY, L3_NCAT, ASSERT_NFLAG);

	Annotations::declare_type(action_meaning_ANNOT,
		ActionsNodes::write_action_meaning_ANNOT);
	Annotations::allow(ACTION_NT, action_meaning_ANNOT);

	Annotations::declare_type(constant_action_name_ANNOT,
		ActionsNodes::write_constant_action_name_ANNOT);
	Annotations::declare_type(constant_action_pattern_ANNOT,
		ActionsNodes::write_constant_action_pattern_ANNOT);
	Annotations::declare_type(constant_explicit_action_ANNOT,
		ActionsNodes::write_constant_explicit_action_ANNOT);
	Annotations::declare_type(constant_named_action_pattern_ANNOT,
		ActionsNodes::write_constant_named_action_pattern_ANNOT);
	Annotations::allow(CONSTANT_NT, constant_action_name_ANNOT);
	Annotations::allow(CONSTANT_NT, constant_action_pattern_ANNOT);
	Annotations::allow(CONSTANT_NT, constant_named_action_pattern_ANNOT);
	Annotations::allow(CONSTANT_NT, constant_explicit_action_ANNOT);
}

@ And for the debugging log:

=
void ActionsNodes::write_action_meaning_ANNOT(text_stream *OUT, parse_node *p) {
	if (Node::get_action_meaning(p)) {
		WRITE(" {action meaning: ");
		ActionPatterns::write(OUT, Node::get_action_meaning(p));
		WRITE("}");
	} 
}
void ActionsNodes::write_constant_action_name_ANNOT(text_stream *OUT, parse_node *p) {
	if (Node::get_constant_action_name(p))
		WRITE(" {action name: %W}",
			ActionNameNames::tensed(Node::get_constant_action_name(p), IS_TENSE));
}
void ActionsNodes::write_constant_action_pattern_ANNOT(text_stream *OUT, parse_node *p) {
	if (Node::get_constant_action_pattern(p)) {
		WRITE(" {action pattern: ");
		ActionPatterns::write(OUT, Node::get_constant_action_pattern(p));
		WRITE("}");
	} 
}
void ActionsNodes::write_constant_explicit_action_ANNOT(text_stream *OUT, parse_node *p) {
	if (Node::get_constant_explicit_action(p)) {
		WRITE(" {explicit action: ");
		ActionPatterns::write(OUT, Node::get_constant_explicit_action(p)->as_described);
		WRITE("}");
	} 
}
void ActionsNodes::write_constant_named_action_pattern_ANNOT(text_stream *OUT,
	parse_node *p) {
	if (Node::get_constant_named_action_pattern(p)) {
		WRITE(" {named action pattern: ");
		Nouns::write(OUT, Node::get_constant_named_action_pattern(p)->as_noun);
		WRITE("}");
	} 
}

@ The ACTION node type is used in //assertions: Assertions// to represent
whole phrases in sentences which are descriptions of actions. It occurs only
when working on copular sentences.

There are in principle two ways that such text could be represented: exactly
specified actions may come out as |PROPER_NOUN_NT| nodes referring to constants
of the |K_stored_action| kind, while vaguely specified ones will be |ACTION_NT|
nodes. The following therefore detects either:

=
int ActionsNodes::is_actionlike(parse_node *p) {
	if (Node::get_type(p) == ACTION_NT) return TRUE;
	if ((K_stored_action) && (Node::get_type(p) == PROPER_NOUN_NT)) {
		parse_node *spec = Node::get_evaluation(p);
		if (Rvalues::is_CONSTANT_of_kind(spec, K_stored_action)) return TRUE;
	}
	return FALSE;
}

@ And this function converts any such proper-noun action clauses to ACTIONs:

=
void ActionsNodes::convert_stored_action_constant(parse_node *p) {
	if (Node::get_type(p) == PROPER_NOUN_NT) {
		parse_node *spec = Node::get_evaluation(p);
		if (Rvalues::is_CONSTANT_of_kind(spec, K_stored_action)) {
			explicit_action *ea = Node::get_constant_explicit_action(spec);
			ActionsNodes::convert_to_ACTION_node(p, ea->as_described);
			return;
		}
	}
}

@ As this exemplifies, |ACTION_NT| nodes are converted from existing ones,
not born:

=
void ActionsNodes::convert_to_ACTION_node(parse_node *p, action_pattern *ap) {
	Node::set_type(p, ACTION_NT);
	Node::set_action_meaning(p, ap);
	p->down = NULL;
}

@ We use the functions above when a copular sentence appears to be creating
something, by making an "X is a Y" sort of sentence.

=
int ActionsNodes::creation(parse_node *px, parse_node *py) {
	@<Intervene to catch behaviour sentences@>;
	@<Intervene to undo a false action detection@>;
	return FALSE;
}

@ Consider:

>> Taking something is proactive behaviour.

Here |Refiner::refine| will correctly report that "proactive behaviour" is
a new term, and give it a |CREATED_NT| node. But we don't want it to become an
object or a value -- we want it to be a new named action pattern. So we
amend the node to |ACTION_NT|. And in general, whenever both sides of a
copular assertion are actionlike, we want to make them |ACTION_NT| nodes.

@<Intervene to catch behaviour sentences@> =
	if ((ActionsNodes::is_actionlike(px)) && (Node::get_type(py) == CREATED_NT))
		Node::set_type(py, ACTION_NT);
	if ((ActionsNodes::is_actionlike(px)) && (ActionsNodes::is_actionlike(py))) {
		ActionsNodes::convert_stored_action_constant(px);
		ActionsNodes::convert_stored_action_constant(py);
	}

@ The second case occurs much less often -- for instance, the only time it comes
up in the test suite is |CHS|, the example "Chronic Hinting Syndrome":

>> Setting is a kind of value. The settings are bright and dull.

Here the first sentence wants to create something called "setting", which
ought to have a |CREATED_NT| node type, but doesn't because it has been read
as an action instead. We correct the spurious |ACTION_NT| to a |CREATED_NT|.

@<Intervene to undo a false action detection@> =
	if ((Node::get_type(px) == ACTION_NT) && (Node::get_type(py) == KIND_NT))
		Node::set_type(px, CREATED_NT);

@ This is also an intervention in an assertion, and comes when a property
is being set to an |ACTION_NT| node. This is where we make the reverse
conversion, and turn such a node back to a |K_stored_action| proper noun,
so that it can indeed be used as a value.

=
int ActionsNodes::unusual_property_value_node(parse_node *py) {
	if (Node::get_type(py) == ACTION_NT) {
		action_pattern *ap = Node::get_action_meaning(py);
		if (ap) {
			parse_node *val = ARvalues::from_action_pattern(ap);
			if (Rvalues::is_CONSTANT_of_kind(val, K_stored_action)) {
				Refiner::give_spec_to_noun(py, val);
				return TRUE;
			}
		}
	}
	return FALSE;
}
