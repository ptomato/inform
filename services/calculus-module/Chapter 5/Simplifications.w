[Simplifications::] Simplifications.

A set of operations which rewrite propositions to make them easier or
quicker to test at run-time without changing their meaning.

@h Golden rules.
The following functions all take a propeosition $\Sigma$ in the parameter
|prop|, and return $\Sigma'$; they set the flag pointed to by |changed| if
they in fact change something. (They are allowed to modify or destroy the
data structure pointed to by |prop|, or indeed to change it in place and
return the same pointer.)

(1) $\Sigma'$ must remain a syntactically correct proposition;
(2) $\Sigma'$ has the same number of free variables as $\Sigma$, and
(3) $\Sigma$ semantically entails $\Sigma'$ and vice versa, that is, for
all possible values of any free variables $\Sigma'$ is true if and only
if $\Sigma$ is.

Rules (1) and (2) are always strictly obeyed. If (3) is also strictly obeyed,
we call the function a "deduction": but if we bend rule (3) to accommodate
the quirky nature of language, we call it a "fudge".

Note that we do not require $\Sigma'$ to be simpler than $\Sigma$ in any
crude sense (say, its number of atoms). We want it to be more convenient
to test at run-time than $\Sigma$ would have been, that's all. But usually
it's a good idea to reduce the number of different variables occurring in it.

@h Simplify the nothing constant (fudge).
The word "nothing" is sometimes a noun ("the holder of the oak tree is
nothing"), sometimes a determiner ("nothing is in the box"). This
doesn't arise with other no- words, such as "nowhere" and "nobody", since
those are not allowed as nouns in Inform.

Here we look for the noun form as one term in a binary predicate, and convert
it to the determiner form unless the predicate is equality. Thus "X is nothing"
is allowed to use the noun form, "X contains nothing" has to use the
determiner form.[1]

[1] In particular "nothing is nothing" compares two identical nouns and is always
true. I thought this was a sentence nobody would write, but Google finds 223,000
hits for it, for example in Peter Hammill's lyrics to "Flight": "He say nothing
is quite what it seems / I say nothing is nothing."

=
pcalc_prop *Simplifications::nothing_constant(pcalc_prop *prop, int *changed) {
	*changed = FALSE;
	#ifdef DETECT_NOTHING_CALCULUS_CALLBACK
	TRAVERSE_VARIABLE(pl);
	TRAVERSE_PROPOSITION(pl, prop)
		if ((Atoms::is_binary_predicate(pl)) &&
			(Atoms::is_equality_predicate(pl) == FALSE)) {
			binary_predicate *bp = RETRIEVE_POINTER_binary_predicate(pl->predicate);
			for (int i=0; i<2; i++) {
				parse_node *C = Terms::constant_underlying(&(pl->terms[i]));
				if (DETECT_NOTHING_CALCULUS_CALLBACK(C)) {
					@<Substitute for the term and quantify with does-not-exist@>;
					PROPOSITION_EDITED(pl, prop);
					break;
				}
			}
		}
	#endif
	return prop;
}

@ Formally, if $B$ is a predicate other than equality, and $N$ is the "nothing" constant,
$$ \Sigma = \cdots B(t, f_X(f_Y(\cdots(N))))\cdots \quad \longrightarrow \quad \Sigma' = \cdots \not\exists v\in\lbrace v\mid K_1(v)\rbrace: B(t, f_X(f_Y(\cdots(v))))\cdots $$
where $v$ is unused in $\Sigma$, and -- note the difference in placing --
$$ \Sigma = \cdots B(f_X(f_Y(\cdots(N))), t)\cdots \quad \longrightarrow \quad \Sigma' = \not\exists v\in\lbrace v\mid K_2(v)\rbrace: \cdots B(f_X(f_Y(\cdots(v))), t)\cdots $$
where $K_1$ and $K_2$ are the kinds of terms 1 and 2 in the predicate $B$.

The difference in where we place the quantifier is important in double-negative
sentences. Consider these:

>> [1] the box does not contain nothing

which produces $\Sigma = \lnot({\it contains}(B, N))$. Here,
|nothing| is part of the object phrase, not the subject phrase, and we need
to quantify it within the OP -- which means, within the negation, because our
recipe for negated sentences was (roughly) SP $\land\lnot($ OP $\land$ VP$)$.
We thus make $\Sigma' = \lnot(\not\exists x:{\it contains}(B, x))$,
although later simplification converts that to $\exists x: {\it contains}(B, x)$,
just as if the original sentence had been "the box contains something".
On the other hand,

>> [2] nothing does not annoy Peter

produces $\Sigma = \lnot({\it annoys}(N, P))$, and now we have
to quantify as $\Sigma' = \not\exists x: \lnot({\it annoys}(x, P))$.

Double-negatives are a little odd. If natural language were really the same as
predicate logic with some grunting sounds for decoration, then a double negative
would always be a positive. In fact that isn't always quite true,[1] but Inform
does consider a double negative to be a positive.

[1] In 18th-century English, for example, the double negative was a way to
emphasise rather than undo negation, just as characters in Aaron Sorkin dramas
are always saying "not for nothing, but..." to mean "it's nothing, but...".

@ The code is simpler than the explanation:

@<Substitute for the term and quantify with does-not-exist@> =
	int nv = Binding::find_unused(prop);
	pcalc_term new_var = Terms::new_variable(nv);
	Binding::substitute_nothing_in_term(&(pl->terms[i]), &new_var);
	pcalc_prop *position = NULL; /* at the front if |nothing| is the SP... */
	if (i == 1) position = pl_prev; /* ...but up close to the predicate if it's the OP */
	/* insert four atoms, in reverse order, at this position: */
	prop = Propositions::insert_atom(prop, position, Atoms::new(DOMAIN_CLOSE_ATOM));
	if (BinaryPredicates::term_kind(bp, i))
		prop = Propositions::insert_atom(prop, position,
			KindPredicates::new_atom(BinaryPredicates::term_kind(bp, i), new_var));
	prop = Propositions::insert_atom(prop, position, Atoms::new(DOMAIN_OPEN_ATOM));
	prop = Propositions::insert_atom(prop, position,
		Atoms::QUANTIFIER_new(not_exists_quantifier, nv, 0));

@h Use listed-in predicates (deduction).
Suppose the source text reads:

>> if X is a density listed in the Table of Solid Stuff, ...

Inform parses "a density listed in the Table of Solid Stuff" as a single
specification, with references to the density column and the Solid Stuff
table. In terms of our calculus, this is just another constant, which we'll call $L$.
At this point the sentence looks like:
$$ {\it is}(X, L) $$
The trouble is that $L$ is really a predicate, acting on some free variable $v$,
because it stands for any value $v$ found in the density column. So we must make
its nature explicit. Every table column has an associated binary predicate,
and we rewrite:
$$ \exists v: {\it number}(v)\land {\it listed}_{\it density}(v, T)\land {\it is}(v, X) $$
This looks extravagant, but later simplification will reduce it to
${\it listed}_{\it density}(X, T)$.

More formally suppose we write $L(C, T)$ for the constant representing "a
C listed in T", and suppose we use the notation $P(\dots t\dots)$ for any
predicate containing a term underlying which is $t$. Let $v$ be a variable
unused in $\Sigma$, and let $K$ be the kind of value of entries in the $C$
column. Then:
$$ \Sigma = \cdots P(\dots L(C, T)\dots) \cdots \quad \longrightarrow \quad \Sigma' = \cdots \exists v: K(v)\land {\it listed}_C(v, T)\land P(\dots v\dots) \cdots $$
where the variable $v$ has replaced the constant $L(C, T)$ underlying one
of the terms of $P$.

Note that this can act twice on the same predicate, if such terms occur
twice. For example,

>> if a crispiness listed in the Table of Salad Stuff is a density listed in the Table of Solid Stuff, ...

generates ${\it is}(L(C_1, T_1), L(C_2, T_2))$. As it happens, Inform can't
compile this efficiently and will produce a problem message to say so, but
the code here does generate the correct proposition,
$$ \exists x: {\it number}(x)\land {\it listed}_{\it Salad}(x, T_1)\land {\it listed}_{\it Solid}(x, T_2). $$

=
#ifdef CORE_MODULE
pcalc_prop *Simplifications::use_listed_in(pcalc_prop *prop, int *changed) {
	TRAVERSE_VARIABLE(pl);

	*changed = FALSE;

	TRAVERSE_PROPOSITION(pl, prop) {
		int j;
		for (j=0; j<pl->arity; j++) {
			parse_node *spec = Terms::constant_underlying(&(pl->terms[j]));
			if ((spec) && (Lvalues::get_storage_form(spec) == TABLE_ENTRY_NT) &&
				(Node::no_children(spec) == 2)) {
				parse_node *col = spec->down;
				parse_node *tab = spec->down->next;
				table_column *tc = Rvalues::to_table_column(col);
				kind *K = Tables::Columns::get_kind(tc);
				if ((K_understanding) && (Kinds::eq(K, K_understanding))) K = K_snippet;
				int nv = Binding::find_unused(prop);
				pcalc_term nv_term = Terms::new_variable(nv);
				prop = Propositions::insert_atom(prop, pl_prev,
					Atoms::binary_PREDICATE_new(Tables::Columns::get_listed_in_predicate(tc),
						nv_term, Terms::new_constant(tab)));
				pcalc_prop *new_KIND = KindPredicates::new_atom(K, nv_term);
				new_KIND->saved_bp = Tables::Columns::get_listed_in_predicate(tc);
				prop = Propositions::insert_atom(prop, pl_prev, new_KIND);
				prop = Propositions::insert_atom(prop, pl_prev,
					Atoms::QUANTIFIER_new(exists_quantifier, nv, 0));
				Binding::substitute_term_in_term(&(pl->terms[j]), &nv_term);
				LocalVariables::add_table_lookup();
				PROPOSITION_EDITED(pl, prop);
			}
		}
	}

	return prop;
}
#endif

@h Simplify negated determiners (deduction).
The negation atom is worth removing wherever possible, since we want to
keep propositions in a flat conjunction form if we can, and the negation
of a string of atoms is therefore a bad thing. We therefore change thus:
$$ \Sigma = \cdots \lnot (Qv\in\lbrace v\mid \phi(v)\rbrace: \psi)\cdots \quad \longrightarrow \quad \Sigma' = \cdots Q'v\in\lbrace v\mid \phi(v)\rbrace: \psi\cdots $$
where $Q'$ is the negation of the generalised quantifier $Q$:
for instance, $V_{<5} y$ becomes $V_{\geq 5} y$.

A curiosity here is that when simplifying during sentence conversion, we
choose not to apply this deduction in the case of $Q = \exists$. This saves us
having to make difficult decisions about the domain set of $Q$ (see below),
and also preserves $\exists v$ atoms in $\Sigma$, which are useful since
they make some of our later simplifications more applicable.

=
pcalc_prop *Simplifications::negated_determiners_nonex(pcalc_prop *prop, int *changed) {
	return Simplifications::negated_determiners(prop, changed, FALSE);
}

pcalc_prop *Simplifications::negated_determiners(pcalc_prop *prop, int *changed,
	int negate_existence_too) {
	TRAVERSE_VARIABLE(pl);

	*changed = FALSE;

	TRAVERSE_PROPOSITION(pl, prop) {
		pcalc_prop *quant_atom;
		if (Propositions::match(pl, 2,
			NEGATION_OPEN_ATOM, NULL,
			QUANTIFIER_ATOM, &quant_atom)) {
			if ((negate_existence_too) ||
				((Atoms::is_existence_quantifier(quant_atom) == FALSE))) {
				prop = Simplifications::prop_ungroup_and_negate_determiner(prop, pl_prev, TRUE);
				PROPOSITION_EDITED(pl, prop);
			}
		}
	}
	return prop;
}

@ And the following useful function actually performs the change. The only
tricky point here is that we store $\exists v$ without domain brackets; so
if $Q$ happens to be $\exists v$ then we have to turn $\lnot(\exists v: \cdots)$
into $\not\exists v\in \lbrace v\mid \cdots\rbrace\cdots$, and it's not
obvious where to place the $\rbrace$. While there's no logical difference --
the proposition means the same wherever we put it -- the assert-propositions
code is better at handling $\exists v\in X: \phi(v)$ than $\exists v\in Y$.
So we want the braces to enclose fixed, unassertable matter -- $v$ being
a container, say -- and the $\phi$ outside the braces should then contain
predicates which can be asserted.

In practice that's way too hard for this function to handle. If |add_domain_brackets|
is true, then it converts
$$ \lnot(\exists v: \cdots) \quad\longrightarrow\quad \not\exists v\in \lbrace v\mid \cdots\rbrace $$
-- that is, it will make the entire negated subproposition the domain of the
quantifier. If |add_domain_brackets| is false, the function will return a
syntactically incorrect proposition lacking the domain brackets, and it's
the caller's responsibility to put that right.

=
pcalc_prop *Simplifications::prop_ungroup_and_negate_determiner(pcalc_prop *prop,
	pcalc_prop *after, int add_domain_brackets) {
	pcalc_prop *quant_atom, *last;
	int fnd;
	if (after == NULL)
		fnd = Propositions::match(prop, 2,
			NEGATION_OPEN_ATOM, NULL,
			QUANTIFIER_ATOM, &quant_atom);
	else
		fnd = Propositions::match(after, 3, ANY_ATOM_HERE, NULL,
			NEGATION_OPEN_ATOM, NULL,
			QUANTIFIER_ATOM, &quant_atom);
	if (fnd) {
		quantifier *quant = quant_atom->quant;
		quantifier *antiquant = Quantifiers::get_negation(quant);
		quant_atom->quant = antiquant;
		prop = Propositions::ungroup_after(prop, after, &last); /* remove negation brackets */
		if ((quant == exists_quantifier) && (add_domain_brackets)) {
			prop = Propositions::insert_atom(prop, quant_atom, Atoms::new(DOMAIN_OPEN_ATOM));
			prop = Propositions::insert_atom(prop, last, Atoms::new(DOMAIN_CLOSE_ATOM));
		}
		if (antiquant == exists_quantifier) {
			prop = Propositions::ungroup_after(prop, quant_atom, NULL); /* remove domain brackets */
		}
		LOGIF(PREDICATE_CALCULUS_WORKINGS,
			"Simplifications::prop_ungroup_and_negate_determiner: $D\n", prop);
	} else internal_error("not a negate-group-determiner");
	return prop;
}

@h Simplify negated satisfiability (deduction).
When simplifying converted sentences, we chose not to use the
|Simplifications::negated_determiners| tactic on existence quantifiers $\exists v$,
partly because it's tricky to establish their domain in a way helpful to
the rest of Inform.

Here we handle a simple case which occurs frequently and where we can indeed
identify the domain well:
$$ \Sigma = \lnot (\exists v: K(v)\land P) \quad \longrightarrow \quad \Sigma' = \not\exists v\in\lbrace v\mid K(v)\rbrace: P $$
where $K$ is a kind, and $P$ is any single predicate other than equality.
(In the case of equality, we'd rather leave matters as they stand, because
substitution will later eliminate all of this anyway.)

=
pcalc_prop *Simplifications::negated_satisfiable(pcalc_prop *prop, int *changed) {
	pcalc_prop *quant_atom, *predicate_atom, *kind_atom;
	*changed = FALSE;
	if ((Propositions::match(prop, 6,
		NEGATION_OPEN_ATOM, NULL,
		QUANTIFIER_ATOM, &quant_atom,
		PREDICATE_ATOM, &kind_atom, kind_up_family,
		PREDICATE_ATOM, &predicate_atom, NULL,
		NEGATION_CLOSE_ATOM, NULL,
		END_PROP_HERE, NULL)) &&
		(Atoms::is_existence_quantifier(quant_atom)) &&
		(Atoms::is_equality_predicate(predicate_atom) == FALSE) &&
		(kind_atom->terms[0].variable == quant_atom->terms[0].variable)) {
		prop = Simplifications::prop_ungroup_and_negate_determiner(prop, NULL, FALSE);
		prop = Propositions::insert_atom(prop, quant_atom, Atoms::new(DOMAIN_OPEN_ATOM));
		prop = Propositions::insert_atom(prop, kind_atom, Atoms::new(DOMAIN_CLOSE_ATOM));
		*changed = TRUE;
	}
	return prop;
}

@h Make kind requirements explicit (deduction).
Many predicates contain implicit requirements about the kinds of their terms.
For instance, if $R$ relates a door to a number, then $R(x,y)$ can only be
true if $x$ is a door and $y$ is a number. We insert these requirements
explicitly in order to defend the code testing $R$; it ensures we never have
to test bogus values. We need do this only for variables, as with more
constants and functions type-checking will certainly be able to test their
kind in any event (whereas a free variable is anonymous enough that we can't
necessarily know by other means).

Formally, let $K_1$ and $K_2$ be the kinds of value of terms 1 and 2 of the
binary predicate $R$. Let $v$ be a variable. Then:
$$ \Sigma = \cdots R(v, t)\cdots \quad \longrightarrow \quad \Sigma' = \cdots K_1(v)\land R(v, t) $$
$$ \Sigma = \cdots R(t, v)\cdots \quad \longrightarrow \quad \Sigma' = \cdots K_2(v)\land R(t, v) $$
and therefore, if both cases occur,
$$ \Sigma = \cdots R(v, w)\cdots \quad \longrightarrow \quad \Sigma' = \cdots K_1(v)\land K_2(w)\land R(v, w) $$

Some of these new kind atoms are unnecessary, but |Simplifications::redundant_kinds| will
detect and remove those.

Why do we do this for binary predicates, but not unary predicates? The answer
is that there's no need, and it's impracticable anyway, because adjectives
are allowed to have multiple definitions for different kinds of value, and
because the code testing them is written to cope properly with bogus values.

=
pcalc_prop *Simplifications::make_kinds_of_value_explicit(pcalc_prop *prop, int *changed) {
	TRAVERSE_VARIABLE(pl);

	TRAVERSE_PROPOSITION(pl, prop)
		if (Atoms::is_binary_predicate(pl)) {
			int i;
			binary_predicate *bp = RETRIEVE_POINTER_binary_predicate(pl->predicate);
			for (i=1; i>=0; i--) {
				int v = pl->terms[i].variable;
				if (v >= 0) {
					kind *K = BinaryPredicates::term_kind(bp, i);
					if (K) {
						pcalc_prop *new_KIND = KindPredicates::new_atom(K, Terms::new_variable(v));
						new_KIND->saved_bp = bp;
						prop = Propositions::insert_atom(prop, pl_prev, new_KIND);
					}
					*changed = TRUE;
				}
			}
		}
	return prop;
}

@h Remove redundant kind predicates (deduction).
Propositions often contain more kind predicates than they need, not least as a
result of |Simplifications::make_kinds_of_value_explicit|. Here we remove some of
those, and move the survivors to what we consider the best positions within
the line. For reasons to be revealed below, we run this process twice over:

=
pcalc_prop *Simplifications::redundant_kinds(pcalc_prop *prop, int *changed) {
	int c1 = FALSE, c2 = FALSE;
	prop = Simplifications::simp_redundant_kinds_dash(prop, prop, 1, &c1);
	prop = Simplifications::simp_redundant_kinds_dash(prop, prop, 1, &c2);
	if ((c1) || (c2)) *changed = TRUE; else *changed = FALSE;
	return prop;
}

@ This function works recursively on subexpressions within the main
proposition. These all begin and end with matched open and close brackets,
with one exception: the main proposition itself.

|start_group| represents the first atom of the expression (the open
bracket, in most cases) and |start_level| the level of bracket nesting
at that point. This is 1 for the main proposition, but 0 for subexpressions,
so that inside the brackets the main content will be at level 1.

This would all go wrong if the proposition were not well-formed, but we
know that it is -- an internal error would have been thrown if not.

=
pcalc_prop *Simplifications::simp_redundant_kinds_dash(pcalc_prop *prop,
	pcalc_prop *start_group, int start_level, int *changed) {
	pcalc_prop *optimal_kind_placings_domain[26], *optimal_kind_placings_statement[26];

	@<Recursively simplify all subexpressions first@>;
	@<Find optimal positions for kind predicates@>;
	@<Strike out redundant kind predicates applied to variables@>;
	@<Strike out tautological kind predicates applied to constants@>;

	return prop;
}

@ For all of the atoms in the body of the group we're working on, the bracket
level will be 1. When it raises to 2, then, we begin a subexpression, and
we recurse into it. (We don't recurse at levels 3 and up because the level 2
call will already have taken care of those sub-sub-expressions.)

@<Recursively simplify all subexpressions first@> =
	TRAVERSE_VARIABLE(pl);
	int blevel = start_level;
	TRAVERSE_PROPOSITION(pl, start_group) {
		if (Atoms::is_opener(pl->element)) {
			blevel++;
			if (blevel == 2)
				prop = Simplifications::simp_redundant_kinds_dash(prop, pl, 0, changed);
		}
		if (Atoms::is_closer(pl->element)) blevel--;
		if (blevel == 0) break;
	}

@ Suppose we have a kind predicate $K(v)$ applied to a variable. What would
be the best place to put this? Generally speaking, we want it as early as
possible, because tests of $K$ are cheap and this will keep running time
low in compiled code. On the other hand we must not move it outside the
current subexpression. The doctrine is:

(i) if $v$ is unbound {\it within the subexpression} then $K(v)$ should
move right to the front;
(ii) if $v$ is bound by $\exists$, then $K(v)$ should move immediately
after $\exists v$;
(iii) if $v$ is bound by $Q v\in\lbrace v\mid \phi(v)\rbrace$ then any
$K(v)$ occurring in the domain $\phi(v)$ should move to the front of $v$,
whereas any later $K(v)$ should move after the domain closing, except
(iv) where $v$ is bound by $\not\exists v\in\lbrace v\mid \phi(v)\rbrace$,
when $K(v)$ should move into the domain set, even if it occurs in the
statement.

Rule (iv) there looks a little surprising. For instance, it causes
$$ \Sigma = \not\exists x\in\lbrace x\mid {\it thing}(x)\land{\it contains}(B, x)\rbrace : {\it container}(x)\land {\it open(x)} \quad \longrightarrow \quad $$
$$ \Sigma' = \not\exists x\in\lbrace x\mid {\it container}(x)\land{\it thing}(x)\land{\it contains}(B, x)\rbrace : {\it open(x)}. $$
These are logically equivalent because $\not\exists$ behaves that way --
they wouldn't be equivalent for other quantifiers. Rule (iii) would have
said no movement was necessary; the reason we made the move is that it
makes $\Sigma'$ possible to assert with "now", as in the phrase "now
nothing in the Ballroom is an open container".

The following calculates two arrays: |optimal_kind_placings_domain| marks the
start of $\phi$ for each variable $v$, while |optimal_kind_placings_statement|
marks the start of the statement following the quantifier.

@<Find optimal positions for kind predicates@> =
	TRAVERSE_VARIABLE(pl);
	int bvsp = 0, bound_vars_stack[26];
	int blevel = start_level, j;

	for (j=0; j<26; j++) {
		optimal_kind_placings_domain[j] = (start_level == 1)?NULL:start_group;
		optimal_kind_placings_statement[j] = optimal_kind_placings_domain[j];
	}

	TRAVERSE_PROPOSITION(pl, start_group) {
		if (Atoms::is_opener(pl->element)) blevel++;
		if (Atoms::is_closer(pl->element)) blevel--;
		if (blevel == 0) break;
		pcalc_prop *dom;
		if (Propositions::match(pl, 2,
				QUANTIFIER_ATOM, NULL,
				DOMAIN_OPEN_ATOM, &dom)) {
			if ((Atoms::is_existence_quantifier(pl)) ||
				(Atoms::is_nonexistence_quantifier(pl)))
				bound_vars_stack[bvsp++] = -1;
			else
				bound_vars_stack[bvsp++] = pl->terms[0].variable;
			optimal_kind_placings_domain[pl->terms[0].variable] = dom;
			optimal_kind_placings_statement[pl->terms[0].variable] = dom;
		} else if (Atoms::is_existence_quantifier(pl)) {
			optimal_kind_placings_domain[pl->terms[0].variable] = pl;
			optimal_kind_placings_statement[pl->terms[0].variable] = pl;
		}
		if (pl->element == DOMAIN_CLOSE_ATOM) {
			int v = bound_vars_stack[--bvsp];
			if (v >= 0) optimal_kind_placings_statement[v] = pl;
		}
	}

@ The following looks at the predicates $K(v)$ applied to variables which
are in the subexpression at the top level. It then does two things:

Suppose $K$ and $L$ are kinds of value such that $L\subseteq K$, and let
$\psi$ be a well-formed proposition. Then
$$ \Sigma = \psi \land L(v) \cdots K(v) \cdots \quad \longrightarrow \quad \Sigma' = \psi \land L(v) \cdots $$
(that is, $K(v)$ is eliminated). This is clearly valid since $L(v)\Rightarrow K(v)$
and $L(v)$ is valid throughout the subexpression after its appearance.

Secondly, and it's not worth finding a logical notation for this, the kind
is moved back to its optimal position, as calculated above.

At first sight, this process only removes redundancies when the stronger
kind appears before the weaker one. What if they occur the other way around?
This is why the simplification is run twice, and why it's important that
the process of moving predicates back to their optimal position reverses
their order. Suppose we start with ${\it person}(x)\land{\it vehicle}(y)\land{\it woman}(x)$.

(1a) On pass 1, "person" occurs before "woman", but it is weaker --
every woman is a person, but not necessarily vice versa -- so neither is
deleted.
(1b) But pass 1 also moves the kinds back, and this produces
${\it woman}(x)\land{\it vehicle}(y)\land{\it person}(x)$.
(2a) On pass 2, the stronger "woman" now occurs before "person", so
we eliminate to get ${\it woman}(x)\land{\it vehicle}(y)$.
(2b) And pass 2 again moves kinds back, producing ${\it vehicle}(y)\land{\it woman}(x)$.

(Because the order is reversed twice, any surviving kind predicates continue
to appear in the same order as they did in the original proposition. This
doesn't matter, but it's tidy.)

@<Strike out redundant kind predicates applied to variables@> =
	TRAVERSE_VARIABLE(pl);
	int domain_passed[26], j;
	int blevel = start_level;

	for (j=0; j<26; j++) domain_passed[j] = FALSE;

	TRAVERSE_PROPOSITION(pl, start_group) {
		for (j=0; j<26; j++)
			if (pl == optimal_kind_placings_statement[j])
				domain_passed[j] = TRUE;
		if (Atoms::is_opener(pl->element)) blevel++;
		if (Atoms::is_closer(pl->element)) blevel--;
		if (blevel == 1) {
			if (KindPredicates::is_kind_atom(pl)) {
				kind *early_kind = KindPredicates::get_kind(pl);
				int v = pl->terms[0].variable;
				if ((v >= 0) && (early_kind)) {
					@<Strike out any subsequent but weaker kind predicate on the same variable@>;
					@<Move this predicate backwards to its optimal position@>;
				}
			}
		}
		if (blevel == 0) break;
	}

@ The noteworthy thing here is that we continue through the subexpression,
deleting any weaker form of $K(v)$ that we find, but also allow ourselves
to continue beyond the subexpression in one case. Suppose we have
$$ Qv\in\lbrace v\mid K(v) \land... \rbrace : L(v) $$
and we are working on the $K(v)$ term. If we continue only to the end of
the current subexpression, that runs out at the $\rbrace$, the end of
the domain specification. So in that one case alone we allow ourselves
to sidestep the domain closure and continue looking for $L(v)$ in the
outer subexpression -- the one which is governed by the quantifier.

@<Strike out any subsequent but weaker kind predicate on the same variable@> =
	TRAVERSE_VARIABLE(gpl);
	int glevel = 1;
	TRAVERSE_PROPOSITION(gpl, pl) {
		if (Atoms::is_opener(gpl->element)) glevel++;
		if (gpl->element == DOMAIN_CLOSE_ATOM) {
			if (glevel > 1) glevel--;
		} else if (Atoms::is_closer(gpl->element)) glevel--;
		if (glevel == 0) break;
		if ((gpl != pl) && (KindPredicates::is_kind_atom(gpl)) && (v == gpl->terms[0].variable)) {
			/* i.e., |gpl| now points to a different kind atom on the same variable */
			kind *later_kind = KindPredicates::get_kind(gpl);
			if ((later_kind) && (Kinds::conforms_to(early_kind, later_kind))) {
				prop = Propositions::delete_atom(prop, gpl_prev);
				PROPOSITION_EDITED_REPEATING_CURRENT(gpl, prop);
			}
		}
	}

@<Move this predicate backwards to its optimal position@> =
	pcalc_prop *best_place = optimal_kind_placings_domain[v];
	if (domain_passed[v]) best_place = optimal_kind_placings_statement[v];
	if (pl_prev != best_place) {
		int state = KindPredicates::is_unarticled_atom(pl_prev);
		prop = Propositions::delete_atom(prop, pl_prev); /* that is, delete the current $K(v)$ */
		pcalc_prop *new_K = KindPredicates::new_atom(early_kind,
			Terms::new_variable(v));
		KindPredicates::set_unarticled(new_K, state);
		prop = Propositions::insert_atom(prop, best_place, new_K); /* insert a new one */
		PROPOSITION_EDITED_REPEATING_CURRENT(pl, prop);
	}

@ Suppose we find a term $K(C)$, where $C$ is a constant in the sense of
predicate calculus. Then there is no need to perform such a test at run-time
because we can determine the kind of $C$ right now and simply compare it.
and compare it against $K$ right now. For instance, ${\it number}(17)$
is bound to be true.

Formally, suppose $C$ is a constant which, when evaluated, has kind of value
$L$. Suppose that $L\subseteq K$ and that $K$ is not a kind of object. Then
$$ \Sigma = \cdots K(C)\cdots \quad \longrightarrow \quad \Sigma' = \cdots\cdots $$
(That is, we eliminate the $K(C)$ term.)

We could clearly go further than this:
(a) Why don't we eliminate $K(C)$ when $K$ is an object, too? Logically this
would be fine, but we choose not to, for two reasons: people sometimes write
phrases in I7 which claim to return a room, say, but sometimes return |nothing|.
Technically this is a violation of type safety. If $t$ is a term representing
a call to this function, then ${\it room}(t)$ ought to be redundant. But in
practice it will protect against the |nothing| value. The other reason is
to ensure that text like "Peter is a man" is not simplified all the way
down to the null proposition (as it clearly can be, if Peter is indeed a man).
That might seem harmless, but means that "now Peter is a man" doesn't produce
the problem message saying that kinds can't be asserted -- a common mistake
made by beginners. It's better consistently to reject all such attempts than
to be clever and allow the ones which are logically redundant.
(b) Why don't we reduce $K(C)$ to falsity when $C$ is a constant clearly not
of the kind $K$, such as ${\it text}(4)$? Again, it would make it harder to
issue a good problem message later, in type-checking; and besides our
calculus lacks a "falsity" atom, so there's no way to store the universally
false proposition which would result if we eliminated every atom this way.
(It also doesn't matter what the running time of compiled code will be if
the proposition is going to fail type-checking anyway.)

@<Strike out tautological kind predicates applied to constants@> =
	TRAVERSE_VARIABLE(pl);
	int blevel = start_level;
	TRAVERSE_PROPOSITION(pl, start_group) {
		if (Atoms::is_opener(pl->element)) blevel++;
		if (Atoms::is_closer(pl->element)) blevel--;
		if (blevel == 1) {
			if (KindPredicates::is_kind_atom(pl)) {
				kind *early_kind = KindPredicates::get_kind(pl);
				parse_node *spec = pl->terms[0].constant;
				kind *K = RVALUE_TO_KIND_FUNCTION(spec);
				if ((K) && (Kinds::Behaviour::is_subkind_of_object(early_kind) == FALSE) &&
					(Kinds::conforms_to(early_kind, K))) {
					prop = Propositions::delete_atom(prop, pl_prev);
					PROPOSITION_EDITED_REPEATING_CURRENT(pl, prop);
				}
			}
		}
	}

@h Turn binary predicates the right way round (deduction).
Recall that BPs are manufactured in pairs, each being the reversal of
the other, in the sense of transposing their terms. Of each pair, one is
considered the canonical way to represent the relation, and is "the right
way round". This function turns all BPs in the proposition the right way
round, if they aren't already. (Equality is always the right way round, so
that is never altered.)

Suppose $B$ is a binary predicate which is marked as the wrong way round,
and $R$ is its reversal. Then we change:
$$ \Sigma = \cdots B(t_1, t_2)\cdots \quad \longrightarrow \quad \Sigma' = \cdots R(t_2, t_1) \cdots $$

=
pcalc_prop *Simplifications::turn_right_way_round(pcalc_prop *prop, int *changed) {
	TRAVERSE_VARIABLE(pl);

	*changed = FALSE;

	TRAVERSE_PROPOSITION(pl, prop) {
		binary_predicate *bp = Atoms::is_binary_predicate(pl);
		if ((bp) && (BinaryPredicates::is_the_wrong_way_round(bp))) {
			pcalc_term pt = pl->terms[0];
			pl->terms[0] = pl->terms[1];
			pl->terms[1] = pt;
			pl->predicate = STORE_POINTER_binary_predicate(BinaryPredicates::get_reversal(bp));
			PROPOSITION_EDITED(pl, prop);
		}
	}
	return prop;
}

@h Simplify region containment (fudge).
Most of Inform's prepositions are unambiguous, but "in" can mean two quite
different relations. Usually it means (direct) containment, but there is an
alternative interpretation as regional containment. "The diamond is in the
teddy bear" is direct containment, but "The diamond is in Northumberland"
is regional containment. We need to separate out these ideas into two
different binary predicates because direct containment has a function $f_D$
allowing simplification of many common sentences, but regional containment
allows no such simplification. Basically: you can be directly contained by
only one thing at a time, but might be in many regions at once.

So far we assume every "in" means the |R_containment|. This is the
point where we choose to divert some uses to |R_regional_containment|.
If $R$ is a constant region name, and $C_D$, $C_R$ are the predicates for
direct and region containment, then
$$ \Sigma = \cdots C_D(t, R)\cdots \quad \longrightarrow \quad \Sigma' = \cdots C_R(t, R)\cdots $$
$$ \Sigma = \cdots C_D(R, t)\cdots \quad \longrightarrow \quad \Sigma' = \cdots C_R(R, t)\cdots $$
Note that a region cannot directly contain any object, except a backdrop.

=
pcalc_prop *Simplifications::region_containment(pcalc_prop *prop, int *changed) {
	*changed = FALSE;
	#ifdef IF_MODULE
	TRAVERSE_VARIABLE(pl);
	TRAVERSE_PROPOSITION(pl, prop) {
		binary_predicate *bp = Atoms::is_binary_predicate(pl);
		if (bp == R_containment) {
			int j;
			for (j=0; j<2; j++) {
				int regionality = FALSE, backdropping = FALSE;
				if (pl->terms[j].constant) {
					kind *KR = Specifications::to_kind(pl->terms[j].constant);
					if (Kinds::Behaviour::is_object_of_kind(KR, K_region)) {
						regionality = TRUE;
					}
				}
				if (pl->terms[1-j].constant) {
					kind *KB = Specifications::to_kind(pl->terms[1-j].constant);
					if (Kinds::Behaviour::is_object_of_kind(KB, K_backdrop))
						backdropping = TRUE;
				}
				if ((regionality) && (!backdropping)) {
					pl->predicate = STORE_POINTER_binary_predicate(R_regional_containment);
					PROPOSITION_EDITED(pl, prop);
				}
			}
		}
	}
	#endif
	return prop;
}

@h Reduce binary predicates (deduction).
If we are able to reduce a binary to a unary predicate, we will probably
gain considerably by being able to eliminate a variable altogether. For
instance, suppose we have "Mme Cholet is in a burrow". This will
initially come out as
$$ \exists x: {\it burrow}(x)\land {\it in}(C, x) $$
To test that proposition requires trying all possible burrows $x$.
But exploiting the fact that Mme Cholet can only be in one place at a
time, we can reduce the binary predicate to equality, thus:
$$ \exists x: {\it burrow}(x)\land {\it is}(f(C), x) $$
where $f$ is the function determining the location of something. A later
simplification can then observe that this tells us what $x$ must be,
and eliminate both quantifier and variable.

Formally, suppose $B$ is a predicate with a function $f_B$ such that $B(x, y)$
is true if and only $y = f_B(x)$. Then:
$$ \Sigma = \cdots B(t_1, t_2) \cdots \quad \longrightarrow \quad \Sigma' = \cdots {\it is}(f_B(t_1), t_2) \cdots $$
Similarly, if there is a function $g_B$ such that $B(x, y)$ if and only if
$x = g_B(y)$ then
$$ \Sigma = \cdots B(t_1, t_2) \cdots \quad \longrightarrow \quad \Sigma' = \cdots {\it is}(t_1, g_B(t_2)) \cdots $$
Not all BPs have these: the reason for our fudge on regional containment (above)
is that direct containment does, but region containment doesn't, and this is
why it was necessary to separate the two out.

=
pcalc_prop *Simplifications::reduce_predicates(pcalc_prop *prop, int *changed) {
	TRAVERSE_VARIABLE(pl);

	*changed = FALSE;

	TRAVERSE_PROPOSITION(pl, prop) {
		binary_predicate *bp = Atoms::is_binary_predicate(pl);
		if (bp)
			for (int j=0; j<2; j++)
				if (BinaryPredicates::get_term_as_fn_of_other(bp, j)) {
					pl->terms[1-j] = Terms::new_function(bp, pl->terms[1-j], 1-j);
					pl->predicate = STORE_POINTER_binary_predicate(R_equality);
					PROPOSITION_EDITED(pl, prop);
				}
	}
	return prop;
}

@h Eliminating determined variables (deduction).
The above operations will try to get as many variables as possible into a
form which makes their values explicit with a predicate ${\it is}(v, t)$.
We detect such equations and use them to eliminate the variable concerned,
where this is safe.

@d NOT_BOUND_AT_ALL 1
@d BOUND_BY_EXISTS 2
@d BOUND_BY_SOMETHING_ELSE 3

=
pcalc_prop *Simplifications::eliminate_redundant_variables(pcalc_prop *prop, int *changed) {
	TRAVERSE_VARIABLE(pl);
	int level, binding_status[26], binding_level[26], binding_sequence[26];
	pcalc_prop *position_of_binding[26];

	*changed = FALSE;

	EliminateVariables:
	@<Find out where and how variables are bound@>;
	level = 0;
	TRAVERSE_PROPOSITION(pl, prop) {
		if (Atoms::is_opener(pl->element)) level++;
		if (Atoms::is_closer(pl->element)) level--;
		if (Atoms::is_equality_predicate(pl)) {
			int j;
			for (j=1; j>=0; j--) {
				int var_to_sub = pl->terms[j].variable;
				int var_in_other_term = Terms::variable_underlying(&(pl->terms[1-j]));
				int var_is_redundant = FALSE, value_can_be_subbed = FALSE;
				@<Decide if the variable is redundant, and if its value can safely be subbed@>;
				if ((var_is_redundant) && (value_can_be_subbed)) {
					int permitted;
					Binding::substitute_term(prop, var_to_sub, pl->terms[1-j],
						TRUE, &permitted, changed);
					if (permitted) {
						LOGIF(PREDICATE_CALCULUS_WORKINGS, "Substituting %c <-- $0\n",
							pcalc_vars[var_to_sub], &(pl->terms[1-j]));
						/* first delete the is(v, t) predicate */
						prop = Propositions::delete_atom(prop, pl_prev);
						/* then unbind the variable, by deleting its exists v quantifier */
						prop = Propositions::delete_atom(prop, position_of_binding[var_to_sub]);
						LOGIF(PREDICATE_CALCULUS_WORKINGS, "After deletion: $D\n", prop);
						binding_status[var_to_sub] = NOT_BOUND_AT_ALL;
						/* then substitute for all other occurrences of v */
						prop = Binding::substitute_term(prop, var_to_sub, pl->terms[1-j],
							FALSE, NULL, changed);
						*changed = TRUE;
						/* since the proposition is now shorter by 2 atoms, this loop terminates */
						goto EliminateVariables;
					}
				}
			}
		}
	}
	Binding::renumber(prop, NULL); /* for the sake of tidiness */
	return prop;
}

@ The information-gathering stage:

@<Find out where and how variables are bound@> =
	int j, c = 0, level = 0;

	for (j=0; j<26; j++) {
		binding_status[j] = NOT_BOUND_AT_ALL;
		binding_level[j] = 0; binding_sequence[j] = 0; position_of_binding[j] = NULL;
	}

	TRAVERSE_PROPOSITION(pl, prop) {
		if (Atoms::is_opener(pl->element)) level++;
		if (Atoms::is_closer(pl->element)) level--;
		if (Atoms::is_quantifier(pl)) {
			int v = pl->terms[0].variable;
			if (Atoms::is_existence_quantifier(pl)) binding_status[v] = BOUND_BY_EXISTS;
			else binding_status[v] = BOUND_BY_SOMETHING_ELSE;
			binding_level[v] = level;
			binding_sequence[v] = c;
			position_of_binding[v] = pl_prev;
		}
		c++;
	}

@ At this point we have a predicate ${\it is}(t, f_A(f_B(\cdots s)))$. Should
the term $t$ be a variable $v$, which is bound by an $\exists v$ atom at the
same level in its subexpression, then we can consider eliminating $v$ by
substituting $v = f_A(f_B(\cdots s))$.

But only if the term $s$ underneath those functions does not make the equation
${\it is}(v, f_A(f_B(\cdots s)))$ implicit. Suppose $s$ depends
on a variable $w$ which is bound and occurs after the binding of $v$.
The value of such a variable $w$ can depend on the value of $v$. Saying that
$v=s$ may therefore not determine a unique value of $v$ at all: it may be
a subtle condition passed by a whole class of possible values, or none.

The simplest example of such circularity is ${\it is}(v, v)$, true for all $v$.
More problematic is ${\it is}(v, f_C(v))$, "$v$ is the container of $v$",
which is never true. Still worse is
$$ \exists v: V_{=2} w: {\it is}(v, w) $$
which literally says there is a value of $v$ equal to two different things --
certainly false. But if we eliminated $v$, we would get just
$$ V_{=2} w $$
which asserts "there are exactly two objects" -- which is certainly not a
valid deduction.

Here |var_to_sub| is $v$ and |var_in_other_term| is $w$, or else they are $-1$
if no variables are present in their respective terms.

@<Decide if the variable is redundant, and if its value can safely be subbed@> =
	if (var_to_sub >= 0) {
		if ((binding_status[var_to_sub] == BOUND_BY_EXISTS)
			&& (binding_level[var_to_sub] == level))
				var_is_redundant = TRUE;

		if ((var_in_other_term < 0)
			|| (binding_status[var_in_other_term] == NOT_BOUND_AT_ALL)
			|| (binding_sequence[var_in_other_term] < binding_sequence[var_to_sub]))
				value_can_be_subbed = TRUE;
	}

@h Simplify non-relation (deduction).
As a result of the previous simplifications, it fairly often happens that we
find a term like
$$ \lnot({\it thing}(f_P(t))) $$
where $f_P$ is the function determining what, if anything, the object $t$ is
a component part of. This comes out of text such as "... not part of something",
asserting first that there is no $y$ such that $t$ is a part of $y$, and then
simplifying to remove the $y$ variable. A term like the one above is then
left behind. But the negation is cumbersome, and makes the proposition harder
to assert or test. Exploiting the fact that $f_P(t)$ is a property
which is either the part-parent or else $N =$ |nothing|, we can simplify to:
$$ {\it is}(f_P(t), N) $$
And similar tricks can be pulled for other various-to-one-object predicates.

Formally, let $B$ be a binary predicate supporting either a function $f_B$
such that $B(x, y)$ iff $f_B(x) = y$, or else such that $B(x, y)$ iff $f_B(y) = x$;
and such that the values of $f_B$ are objects. Let $K$ be a kind of object.
Then:
$$ \Sigma = \cdots \lnot( K(f_B(t))) \cdots \quad \longrightarrow \quad \Sigma' = \cdots {\it is}(f_B(t), N) \cdots $$

A similar trick for kinds of value is not possible, because -- unlike objects --
they have no "not a valid case" value analogous to the non-object |nothing|.

=
pcalc_prop *Simplifications::not_related_to_something(pcalc_prop *prop, int *changed) {
	*changed = FALSE;
	#ifdef PRODUCE_NOTHING_VALUE_CALCULUS_CALLBACK 
	TRAVERSE_VARIABLE(pl);

	TRAVERSE_PROPOSITION(pl, prop) {
		pcalc_prop *kind_atom;
		if (Propositions::match(pl, 3,
			NEGATION_OPEN_ATOM, NULL,
			PREDICATE_ATOM, &kind_atom, kind_up_family,
			NEGATION_CLOSE_ATOM, NULL)) {
			kind *K = KindPredicates::get_kind(kind_atom);
			if (Kinds::Behaviour::is_subkind_of_object(K)) {
				binary_predicate *bp = NULL;
				pcalc_term KIND_term = kind_atom->terms[0];
				if (KIND_term.function) bp = KIND_term.function->bp;
				if ((bp) && (Kinds::eq(K, BinaryPredicates::term_kind(bp, 1)))) {
					/* remove negation grouping */
					prop = Propositions::ungroup_after(prop, pl_prev, NULL); 
					prop = Propositions::delete_atom(prop, pl_prev); /* remove |kind=K| */
					/* now insert equality predicate: */
					prop = Propositions::insert_atom(prop, pl_prev,
						Atoms::binary_PREDICATE_new(R_equality,
							KIND_term, Terms::new_constant(PRODUCE_NOTHING_VALUE_CALCULUS_CALLBACK())));
					PROPOSITION_EDITED(pl, prop);
				}
			}
		}
	}
	#endif
	return prop;
}

@h Convert gerunds to nouns (deduction).
Suppose we write:
= (text as Inform 7)
The funky thing to do is a stored action that varies.
The funky thing to do is waiting.
=
Here "waiting" is a gerund, and although it describes an action it is a
noun (thus a value) rather than a condition. We coerce its constant value
accordingly.

=
#ifdef IF_MODULE
pcalc_prop *Simplifications::convert_gerunds(pcalc_prop *prop, int *changed) {
	*changed = FALSE;

	TRAVERSE_VARIABLE(pl);
	TRAVERSE_PROPOSITION(pl, prop)
		if ((pl->element == PREDICATE_ATOM) && (pl->arity == 2))
			for (int i=0; i<2; i++)
				if (AConditions::is_action_TEST_VALUE(pl->terms[i].constant))
					pl->terms[i].constant =
						AConditions::gerund_from_TEST_VALUE(pl->terms[i].constant);
	return prop;
}
#endif

@h Eliminate to have meaning property ownership (fudge).
The verb "to have" normally means ownership of a physical thing, but it
can also arise from text such as

>> the balloon has weight at most 1

where it's the numerical "weight" property which is owned by the balloon.
At this stage of simplification, the above has produced
$$ {\it atmost}(w, 1)\land {\it is}(B, f_H(w)) $$
where $H$ is the predicate |a_has_b_predicate|. As it stands, this proposition
will fail type-checking, because it contains an implicit free variable -- the
object which owns the weight. We make this explicit by removing
${\it is}(B, f_H(w))$ and replacing all other references to $w$ with "the
weight of $B$".

This is a fudge because it assumes -- possibly wrongly -- that all references
to the weight are to the weight of the same thing. In sufficiently contrived
sentences, this wouldn't be true. No bugs have ever been reported which suggest
that real users run into this.

=
#ifdef CORE_MODULE
pcalc_prop *Simplifications::eliminate_to_have(pcalc_prop *prop, int *changed) {
	*changed = FALSE;

	TRAVERSE_VARIABLE(pl);
	TRAVERSE_PROPOSITION(pl, prop) {
		if (Atoms::is_equality_predicate(pl)) {
			for (int i=0; i<2; i++)
				if ((pl->terms[i].function) &&
					(pl->terms[i].function->bp == a_has_b_predicate) &&
					(pl->terms[i].function->fn_of.constant) && (pl->terms[1-i].constant)) {
					parse_node *spec = pl->terms[i].function->fn_of.constant;
					if (Rvalues::is_CONSTANT_construction(spec, CON_property))
						@<Found an indication of who owns a property@>;
				}
		}
	}

	return prop;
}
#endif

@ So the current atom is ${\it is}(f_H(P), C)$ or ${\it is}(C, f_H(P))$
(according to whether $i$ is 0 or 1), for a property $P$ and a constant
term $C$.

@<Found an indication of who owns a property@> =
	property *prn = Rvalues::to_property(spec);
	parse_node *po_spec =
		Lvalues::new_PROPERTY_VALUE(spec, pl->terms[1-i].constant);
	Node::set_text(po_spec, prn->name);
	int no_substitutions_made;
	prop = Simplifications::prop_substitute_prop_cons(prop, prn, po_spec,
		&no_substitutions_made, pl);
	if (no_substitutions_made > 0) {
		prop = Propositions::delete_atom(prop, pl_prev);
		PROPOSITION_EDITED_REPEATING_CURRENT(pl, prop);
	}

@ Here we make the necessary substitution of "P" with "the P of C",
where $P$ is a property and $C$ the constant value of its owner. We make
this to every occurrence throughout the proposition, except for the one
in the original ${\it is}(f_H(P), C)$ atom, and we count the number of
changes made.

=
#ifdef CORE_MODULE
pcalc_prop *Simplifications::prop_substitute_prop_cons(pcalc_prop *prop, property *prn,
	parse_node *po_spec, int *count, pcalc_prop *not_this) {
	TRAVERSE_VARIABLE(pl);
	int j, c = 0;
	TRAVERSE_PROPOSITION(pl, prop)
		if (pl != not_this)
			for (j=0; j<pl->arity; j++) {
				pcalc_term *pt = &(pl->terms[j]);
				while (pt->function) pt = &(pt->function->fn_of);
				if (pt->constant == NULL) continue;
				if (Rvalues::is_CONSTANT_construction(pt->constant, CON_property)) {
					property *tprn;
					tprn = Rvalues::to_property(pt->constant);
					if (tprn == prn) {
						pt->constant = po_spec;
						c++;
					}
				}
			}
	*count = c;
	return prop;
}
#endif

@h Turn all rooms to everywhere (fudge).
This rather special rule handles the consequences of the English word
"everywhere". Inform reads that as "all rooms", literally "every where",
which is logical but loses the connotation of place -- by "everywhere", we
usually mean "in all rooms", so that the sentence

>> The sky is everywhere.

means the sky is in every room, not that the sky is equal to every room.
Since the literal reading would make no useful sense, Inform fudges the
proposition to change it to the idiomatic one.
$$ \Sigma = \cdots \forall v\in\lbrace v\mid{\it room}(v)\rbrace : {\it is}(v, t) \quad \longrightarrow \quad \Sigma' = \cdots {\it everywhere}(t) $$
$$ \Sigma = \cdots \forall v\in\lbrace v\mid{\it room}(v)\rbrace : {\it is}(t, v) \quad \longrightarrow \quad \Sigma' = \cdots {\it everywhere}(t) $$
$$ \Sigma = \cdots \not\forall v\in\lbrace v\mid{\it room}(v)\rbrace : {\it is}(v, t) \quad \longrightarrow \quad \Sigma' = \cdots \lnot({\it everywhere}(t)) $$
$$ \Sigma = \cdots \not\forall v\in\lbrace v\mid{\it room}(v)\rbrace : {\it is}(t, v) \quad \longrightarrow \quad \Sigma' = \cdots \lnot({\it everywhere}(t)) $$
Note that we match this only at the end of a proposition, where $v$ can
have no other consequence.

=
pcalc_prop *Simplifications::is_all_rooms(pcalc_prop *prop, int *changed) {
	*changed = FALSE;
	return prop;
	#ifdef IF_MODULE
	TRAVERSE_VARIABLE(pl);
	TRAVERSE_PROPOSITION(pl, prop) {
		pcalc_prop *q_atom, *k_atom, *bp_atom;
		if ((Propositions::match(pl, 6,
			QUANTIFIER_ATOM, &q_atom,
			DOMAIN_OPEN_ATOM, NULL,
			PREDICATE_ATOM, &k_atom, kind_up_family,
			DOMAIN_CLOSE_ATOM, NULL,
			PREDICATE_ATOM, &bp_atom, NULL,
			END_PROP_HERE, NULL)) &&
			((Atoms::is_forall_quantifier(q_atom)) || (Atoms::is_notall_quantifier(q_atom))) &&
			(Kinds::eq(KindPredicates::get_kind(k_atom), K_room)) &&
			(bp_atom->arity == 2) &&
			(RETRIEVE_POINTER_binary_predicate(bp_atom->predicate) == R_equality)) {
			int j, v = k_atom->terms[0].variable;
			for (j=0; j<2; j++) {
				if ((bp_atom->terms[1-j].variable == v) && (v >= 0)) {
					prop = Propositions::delete_atom(prop, pl_prev); /* remove |QUANTIFIER_ATOM| */
					prop = Propositions::delete_atom(prop, pl_prev); /* remove |DOMAIN_OPEN_ATOM| */
					prop = Propositions::delete_atom(prop, pl_prev); /* remove |kind=K| */
					prop = Propositions::delete_atom(prop, pl_prev); /* remove |DOMAIN_CLOSE_ATOM| */
					prop = Propositions::delete_atom(prop, pl_prev); /* remove |PREDICATE_ATOM| */
					if (Atoms::is_notall_quantifier(q_atom))
						prop = Propositions::insert_atom(prop, pl_prev,
							Atoms::new(NEGATION_CLOSE_ATOM));
					prop = Propositions::insert_atom(prop, pl_prev,
						WherePredicates::everywhere_up(bp_atom->terms[j]));
					if (Atoms::is_notall_quantifier(q_atom))
						prop = Propositions::insert_atom(prop, pl_prev,
							Atoms::new(NEGATION_OPEN_ATOM));
					PROPOSITION_EDITED(pl, prop);
					break;
				}
			}
		}
		if ((Propositions::match(pl, 6,
			QUANTIFIER_ATOM, &q_atom,
			DOMAIN_OPEN_ATOM, NULL,
			PREDICATE_ATOM, &k_atom, kind_up_family,
			DOMAIN_CLOSE_ATOM, NULL,
			PREDICATE_ATOM, &bp_atom, NULL,
			END_PROP_HERE, NULL)) &&
			(Atoms::is_nonexistence_quantifier(q_atom)) &&
			(Kinds::eq(KindPredicates::get_kind(k_atom), K_room)) &&
			(KindPredicates::is_composited_atom(k_atom)) &&
			(bp_atom->arity == 2) &&
			(RETRIEVE_POINTER_binary_predicate(bp_atom->predicate) == R_equality)) {
			int j, v = k_atom->terms[0].variable;
			for (j=0; j<2; j++) {
				if ((bp_atom->terms[1-j].variable == v) && (v >= 0)) {
					prop = Propositions::delete_atom(prop, pl_prev); /* remove |QUANTIFIER_ATOM| */
					prop = Propositions::delete_atom(prop, pl_prev); /* remove |DOMAIN_OPEN_ATOM| */
					prop = Propositions::delete_atom(prop, pl_prev); /* remove |kind=K| */
					prop = Propositions::delete_atom(prop, pl_prev); /* remove |DOMAIN_CLOSE_ATOM| */
					prop = Propositions::delete_atom(prop, pl_prev); /* remove |PREDICATE_ATOM| */
					prop = Propositions::insert_atom(prop, pl_prev,
						WherePredicates::nowhere_up(bp_atom->terms[j]));
					PROPOSITION_EDITED(pl, prop);
					break;
				}
			}
		}
	}
	return prop;
	#endif
}

@h Everywhere and nowhere (fudge).
Similarly, if the proposition expresses the idea of "nowhere" or "everywhere"
by spelling this out in quantifiers about being no place or every place, then
replace those with uses of the special unary predicates for "nowhere" and
"everywhere".

=
pcalc_prop *Simplifications::everywhere_and_nowhere(pcalc_prop *prop, int *changed) {
	*changed = FALSE;
	#ifdef IF_MODULE
	TRAVERSE_VARIABLE(pl);
	TRAVERSE_PROPOSITION(pl, prop) {
		pcalc_prop *q_atom, *k_atom, *bp_atom;
		if ((Propositions::match(pl, 6,
			QUANTIFIER_ATOM, &q_atom,
			DOMAIN_OPEN_ATOM, NULL,
			PREDICATE_ATOM, &k_atom, kind_up_family,
			DOMAIN_CLOSE_ATOM, NULL,
			PREDICATE_ATOM, &bp_atom, NULL,
			END_PROP_HERE, NULL)) &&
			((Atoms::is_forall_quantifier(q_atom)) ||
				(Atoms::is_notall_quantifier(q_atom)) ||
				(Atoms::is_nonexistence_quantifier(q_atom))) &&
			(Kinds::eq(KindPredicates::get_kind(k_atom), K_room)) &&
			(bp_atom->arity == 2)) {
			binary_predicate *bp = RETRIEVE_POINTER_binary_predicate(bp_atom->predicate);
			if (((Atoms::is_nonexistence_quantifier(q_atom) == FALSE) && (bp == R_containment)) ||
				(bp == room_containment_predicate)) {
				int j, v = k_atom->terms[0].variable;
				for (j=0; j<2; j++) {
					if ((bp_atom->terms[1-j].variable == v) && (v >= 0)) {
						prop = Propositions::delete_atom(prop, pl_prev); /* remove |QUANTIFIER_ATOM| */
						prop = Propositions::delete_atom(prop, pl_prev); /* remove |DOMAIN_OPEN_ATOM| */
						prop = Propositions::delete_atom(prop, pl_prev); /* remove |kind=K| */
						prop = Propositions::delete_atom(prop, pl_prev); /* remove |DOMAIN_CLOSE_ATOM| */
						prop = Propositions::delete_atom(prop, pl_prev); /* remove |PREDICATE_ATOM| */
						if (Atoms::is_notall_quantifier(q_atom))
							prop = Propositions::insert_atom(prop, pl_prev,
								Atoms::new(NEGATION_CLOSE_ATOM));
						pcalc_prop *new_atom;
						if (Atoms::is_nonexistence_quantifier(q_atom))
							new_atom = WherePredicates::nowhere_up(bp_atom->terms[j]);
						else
							new_atom = WherePredicates::everywhere_up(bp_atom->terms[j]);
						prop = Propositions::insert_atom(prop, pl_prev, new_atom);
						if (Atoms::is_notall_quantifier(q_atom))
							prop = Propositions::insert_atom(prop, pl_prev,
								Atoms::new(NEGATION_OPEN_ATOM));
						PROPOSITION_EDITED(pl, prop);
						break;
					}
				}
			}
		}
	}
	#endif
	return prop;
}
