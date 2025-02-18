[Kits::] Kit Services.

Behaviour specific to copies of the kit genre.

@h Scanning metadata.
Metadata for kits is stored in the following structure. "Attachment" for a
kit is the process of taking the Inter code from a binary Inter file in the
kit directory and merging it into code already generated by the |core|
module of |inform7|.

=
typedef struct inform_kit {
	struct inbuild_copy *as_copy;

	struct text_stream *attachment_point; /* where in the Inter hierarchy to attach this */
	int priority; /* lower kits are attached before higher ones */

	struct text_stream *early_source; /* additional source text to spool in */
	struct linked_list *ittt; /* of |inform_kit_ittt| */
	struct linked_list *kind_definitions; /* of |text_stream| */
	struct linked_list *extensions; /* of |inbuild_requirement| */
	struct linked_list *activations; /* of |element_activation| */
	struct text_stream *index_structure; /* for indexing projects using this kit */
	int defines_Main; /* does the Inter code in this kit define the |Main| routine? */
	int supports_nl; /* does the Inter code in this kit support a natural language extension? */
	CLASS_DEFINITION
} inform_kit;

@ Kits come with an "if this then that" service for including other kits,
and we represent rules with the following:

=
typedef struct inform_kit_ittt {
	struct text_stream *if_name;
	int if_included;
	struct text_stream *then_name;
	CLASS_DEFINITION
} inform_kit_ittt;

@ Kits can also enable elements of the Inform programming language: that is,
enable compiler support for them. For example, the WorldModelKit enables
interactive fiction features of the compiler, but BasicInformKit does not.

=
typedef struct element_activation {
	struct text_stream *element_name;
	int activate;
	CLASS_DEFINITION
} element_activation;

@ Here goes, then:

=
void Kits::scan(inbuild_copy *C) {
	inform_kit *K = CREATE(inform_kit);
	K->as_copy = C;
	if (C == NULL) internal_error("no copy to scan");
	Copies::set_metadata(C, STORE_POINTER_inform_kit(K));

	K->attachment_point = Str::new();
	WRITE_TO(K->attachment_point, "/main/%S", C->edition->work->title);
	K->priority = 10;

	K->early_source = NULL;
	K->ittt = NEW_LINKED_LIST(inform_kit_ittt);
	K->kind_definitions = NEW_LINKED_LIST(text_stream);
	K->extensions = NEW_LINKED_LIST(inbuild_requirement);
	K->activations = NEW_LINKED_LIST(element_activation);
	K->index_structure = NULL;
	K->defines_Main = FALSE;
	K->supports_nl = FALSE;

	filename *F = Filenames::in(C->location_if_path, I"kit_metadata.txt");
	TextFiles::read(F, FALSE,
		NULL, FALSE, Kits::read_metadata, NULL, (void *) C);
}

@ The following reads line by line through the |kit_metadata.txt| file:

=
void Kits::read_metadata(text_stream *text, text_file_position *tfp, void *state) {
	inbuild_copy *C = (inbuild_copy *) state;
	inform_kit *K = KitManager::from_copy(C);
	match_results mr = Regexp::create_mr();
	if ((Str::is_whitespace(text)) || (Regexp::match(&mr, text, L" *#%c*"))) {
		;
	} else if (Regexp::match(&mr, text, L"version: (%C+)"))
		C->edition->version = VersionNumbers::from_text(mr.exp[0]);
	else if (Regexp::match(&mr, text, L"compatibility: (%c+)")) @<Add compatibility@>
	else if (Regexp::match(&mr, text, L"defines Main: yes")) K->defines_Main = TRUE;
	else if (Regexp::match(&mr, text, L"defines Main: no")) K->defines_Main = FALSE;
	else if (Regexp::match(&mr, text, L"natural language: yes")) K->supports_nl = TRUE;
	else if (Regexp::match(&mr, text, L"natural language: no")) K->supports_nl = FALSE;
	else if (Regexp::match(&mr, text, L"insert: (%c*)")) @<Add early source@>
	else if (Regexp::match(&mr, text, L"priority: (%d*)"))
		K->priority = Str::atoi(mr.exp[0], 0);
	else if (Regexp::match(&mr, text, L"kinds: (%C+)"))
		ADD_TO_LINKED_LIST(Str::duplicate(mr.exp[0]), text_stream, K->kind_definitions);
	else if (Regexp::match(&mr, text, L"extension: version (%c+?) of (%c+) by (%c+)"))
		@<Add versioned extension@>
	else if (Regexp::match(&mr, text, L"extension: (%c+) by (%c+)"))
		@<Add unversioned extension@>
	else if (Regexp::match(&mr, text, L"activate: (%c+)"))
		Kits::activation(K, mr.exp[0], TRUE);
	else if (Regexp::match(&mr, text, L"deactivate: (%c+)"))
		Kits::activation(K, mr.exp[0], FALSE);
	else if (Regexp::match(&mr, text, L"dependency: if (%C+) then (%C+)"))
		Kits::dependency(K, mr.exp[0], TRUE, mr.exp[1]);
	else if (Regexp::match(&mr, text, L"dependency: if not (%C+) then (%C+)"))
		Kits::dependency(K, mr.exp[0], FALSE, mr.exp[1]);
	else if (Regexp::match(&mr, text, L"index from: (%c*)"))
		K->index_structure = Str::duplicate(mr.exp[0]);
	else {
		TEMPORARY_TEXT(err)
		WRITE_TO(err, "unreadable instruction '%S'", text);
		Copies::attach_error(C, CopyErrors::new_T(KIT_MISWORDED_CE, -1, err));
		DISCARD_TEXT(err)	
	}
	Regexp::dispose_of(&mr);
}

@<Add compatibility@> =
	compatibility_specification *CS = Compatibility::from_text(mr.exp[0]);
	if (CS) C->edition->compatibility = CS;
	else {
		TEMPORARY_TEXT(err)
		WRITE_TO(err, "cannot read compatibility '%S'", mr.exp[0]);
		Copies::attach_error(C, CopyErrors::new_T(KIT_MISWORDED_CE, -1, err));
		DISCARD_TEXT(err)
	}

@<Add early source@> =
	K->early_source = Str::duplicate(mr.exp[0]);
	WRITE_TO(K->early_source, "\n\n");

@<Add versioned extension@> =
	inbuild_work *work = Works::new(extension_genre, mr.exp[1], mr.exp[2]);
	semantic_version_number V = VersionNumbers::from_text(mr.exp[0]);
	if (VersionNumbers::is_null(V)) {
		TEMPORARY_TEXT(err)
		WRITE_TO(err, "cannot read version number '%S'", mr.exp[0]);
		Copies::attach_error(C, CopyErrors::new_T(KIT_MISWORDED_CE, -1, err));
		DISCARD_TEXT(err)
	} else {
		inbuild_requirement *req = Requirements::new(work,
			VersionNumberRanges::compatibility_range(V));
		ADD_TO_LINKED_LIST(req, inbuild_requirement, K->extensions);
	}

@<Add unversioned extension@> =
	inbuild_work *work = Works::new(extension_genre, mr.exp[0], mr.exp[1]);
	inbuild_requirement *req = Requirements::any_version_of(work);
	ADD_TO_LINKED_LIST(req, inbuild_requirement, K->extensions);

@ We provide if this then that, where |inc| is true, and if this then not that,
where it's false.

=
void Kits::dependency(inform_kit *K, text_stream *if_text, int inc, text_stream *then_text) {
	inform_kit_ittt *ITTT = CREATE(inform_kit_ittt);
	ITTT->if_name = Str::duplicate(if_text);
	ITTT->if_included = inc;
	ITTT->then_name = Str::duplicate(then_text);
	ADD_TO_LINKED_LIST(ITTT, inform_kit_ittt, K->ittt);
}

@ Language elements can similarly be activated or deactivated, though the
latter may not be useful in practice:

=
void Kits::activation(inform_kit *K, text_stream *name, int act) {
	element_activation *EA = CREATE(element_activation);
	EA->element_name = Str::duplicate(name);
	EA->activate = act;
	ADD_TO_LINKED_LIST(EA, element_activation, K->activations);
}

@h The kits included by a project.
A project can call this to obtain the |inform_kit| structure for the copy of
a kit, going only on a name such as |BasicInformKit|:

=
inform_kit *Kits::find_by_name(text_stream *name, linked_list *nest_list) {
	inbuild_requirement *req =
		Requirements::any_version_of(Works::new(kit_genre, name, I""));
	inbuild_search_result *R = Nests::search_for_best(req, nest_list);
	if (R == NULL) Errors::fatal_with_text("cannot find kit '%S'", name);
	inbuild_copy *C = R->copy;
	return KitManager::from_copy(C);
}

@ The ITTT process for a project calls this to see if the ITTT rules for
a |K| require further kit dependencies to be added to the project: if they
do, then the dependencies are added and we return |TRUE|. If there was
nothing to do, we return |FALSE|.

=
int Kits::perform_ittt(inform_kit *K, inform_project *project, int parity) {
	int changes_made = FALSE;
	inform_kit_ittt *ITTT;
	LOOP_OVER_LINKED_LIST(ITTT, inform_kit_ittt, K->ittt)
		if ((ITTT->if_included == parity) &&
			(Projects::uses_kit(project, ITTT->then_name) == FALSE) &&
			(Projects::uses_kit(project, ITTT->if_name) == ITTT->if_included)) {
			Projects::add_kit_dependency(project, ITTT->then_name, NULL, K);
			changes_made = TRUE;
		}
	return changes_made;
}

@h Kind definitions.
The base kinds for the Inform language, such as "real number" or "text", are
not defined in high-level source text, nor by Inter, but by special configuration
files held in the |kinds| subdirectory of the kits used. The following function
loads the base kinds in a kit |K|:

=
#ifdef CORE_MODULE
void Kits::load_built_in_kind_constructors(inform_kit *K) {
	text_stream *segment;
	LOOP_OVER_LINKED_LIST(segment, text_stream, K->kind_definitions) {
		pathname *P = Pathnames::down(K->as_copy->location_if_path, I"kinds");
		filename *F = Filenames::in(P, segment);
		LOG("Loading kinds definitions from %f\n", F);
		Kits::interpret_neptune(F);
	}
}
#endif

@ Using this rudimentary interpreter:

=
#ifdef CORE_MODULE
void Kits::interpret_neptune(filename *neptune_file) {
	FILE *Input_File = NULL;
	int col = 1, cr, lc = 0;
	TEMPORARY_TEXT(heading_name)
	@<Open a file for input, if necessary@>;
	TEMPORARY_TEXT(command)
	TEMPORARY_TEXT(argument)
	do {
		Str::clear(command);
		Str::clear(argument);
		@<Read next character from I6T stream@>;
		if (cr == EOF) break;
		lc++;
		if ((cr == 10) || (cr == 13)) continue; /* skip blank lines here */
		@<Read rest of line as argument@>;
		if ((Str::get_first_char(argument) == '!') ||
			(Str::get_first_char(argument) == 0)) continue; /* skip blanks and comments */
		text_file_position tfp = TextFiles::at(neptune_file, lc);				
		parse_node *cs = current_sentence;
		current_sentence = NULL;
		NeptuneFiles::read_command(argument, &tfp);
		current_sentence = cs;
	} while (cr != EOF);
	DISCARD_TEXT(command)
	DISCARD_TEXT(argument)
	if (Input_File) { if (DL) STREAM_FLUSH(DL); fclose(Input_File); }
	DISCARD_TEXT(heading_name)
}
#endif

@<Open a file for input, if necessary@> =
	if (neptune_file) {
		Input_File = Filenames::fopen(neptune_file, "r");
		if (Input_File == NULL) {
			LOG("Filename was %f\n", neptune_file);
			StandardProblems::unlocated_problem(Task::syntax_tree(),
				_p_(BelievedImpossible), /* or anyway not usefully testable */
				"I couldn't open a Neptune file for defining built-in kinds.");
		}
	}

@ I6 template files are encoded as ISO Latin-1, not as Unicode UTF-8, so
ordinary |fgetc| is used, and no BOM marker is parsed. Lines are assumed
to be terminated with either |0x0a| or |0x0d|. (Since blank lines are
harmless, we take no trouble over |0a0d| or |0d0a| combinations.) The
built-in template files, almost always the only ones used, are line
terminated |0x0a| in Unix fashion.

@<Read next character from I6T stream@> =
	if (Input_File) cr = fgetc(Input_File);
	else cr = EOF;
	col++; if ((cr == 10) || (cr == 13)) col = 0;

@ We get here when reading a kinds template file. Note that initial and
trailing white space on the line is deleted: this makes it easier to lay
out I6T template files tidily.

@<Read rest of line as argument@> =
	Str::clear(argument);
	if (Characters::is_space_or_tab(cr) == FALSE) PUT_TO(argument, cr);
	int at_start = TRUE;
	while (TRUE) {
		@<Read next character from I6T stream@>;
		if ((cr == 10) || (cr == 13)) break;
		if ((at_start) && (Characters::is_space_or_tab(cr))) continue;
		PUT_TO(argument, cr); at_start = FALSE;
	}
	while (Characters::is_space_or_tab(Str::get_last_char(argument)))
		Str::delete_last_character(argument);

@h Language element activation.
Note that this function is meaningful only when this module is part of the
|inform7| executable, and it invites us to activate or deactivate language
features as |K| would like.

=
#ifdef CORE_MODULE
void Kits::activate_elements(inform_kit *K) {
	element_activation *EA;
	LOOP_OVER_LINKED_LIST(EA, element_activation, K->activations) {
		plugin *P = PluginManager::parse(EA->element_name);
		if (P == NULL) {
			StandardProblems::sentence_problem(Task::syntax_tree(), _p_(Untestable),
				"one of the Inform kits made reference to a language segment "
				"which does not exist",
				"which suggests that Inform is not properly installed, unless "
				"you are experimenting with new kits.");
		} else {
			if (EA->activate) PluginManager::activate(P);
			else PluginManager::deactivate(P);
		}
	}
}
#endif

@h Early source.
As we have seen, kits can ask for extensions to be included.

As a last resort, a kit can also ask for a sentence or two to be mandatorily
included in the source text for any project using it. This text appears very
early on, and can't do much, but could for example set use options.

This function simply writes out such sentences, so that they can be fed
into the lexer by our caller.

=
void Kits::early_source_text(OUTPUT_STREAM, inform_kit *K) {
	inbuild_requirement *req;
	LOOP_OVER_LINKED_LIST(req, inbuild_requirement, K->extensions) {
		WRITE("Include ");
		if (VersionNumberRanges::is_any_range(req->version_range) == FALSE) {
			semantic_version_number V = req->version_range->lower.end_value;
			WRITE("version %v of ", &V);
		}
		WRITE("%S by %S.\n\n", req->work->title, req->work->author_name);
	}
	if (K->early_source) WRITE("%S\n\n", K->early_source);
}

linked_list *Kits::inter_paths(linked_list *L) {
	linked_list *inter_paths = NEW_LINKED_LIST(pathname);
	inbuild_nest *N;
	LOOP_OVER_LINKED_LIST(N, inbuild_nest, L)
		ADD_TO_LINKED_LIST(KitManager::path_within_nest(N), pathname, inter_paths);
	return inter_paths;
}

@h Build graph.
The build graph for a kit is quite extensive, since a kit contains Inter
binaries for four different architectures; and each of those has a
dependency on every section file of the web of Inform 6 source for the kit.
If there are $S$ sections then the graph has $S+5$ vertices and $4(S+1)$ edges.

Note that ITTT rules do not affect the build graph; they affect only how a
project uses the kit, and therefore they affect the project's build graph but
not ours.

=
void Kits::construct_graph(inform_kit *K) {
	RUN_ONLY_IN_PHASE(GRAPH_CONSTRUCTION_INBUILD_PHASE)
	if (K == NULL) return;
	inbuild_copy *C = K->as_copy;
	pathname *P = C->location_if_path;
	build_vertex *KV = C->vertex; /* the kit vertex */
	linked_list *BVL = NEW_LINKED_LIST(build_vertex); /* list of vertices for the binaries */
	@<Add build edges to the binaries for each architecture@>;

	web_md *Wm = WebMetadata::get_without_modules(C->location_if_path, NULL);

	build_vertex *CV = Graphs::file_vertex(Wm->contents_filename); /* the contents page vertex */
	@<Add build edges from the binary vertices to the contents vertex@>;

	@<Add build edges from the binary vertices to each section vertex@>;

	inbuild_requirement *req;
	LOOP_OVER_LINKED_LIST(req, inbuild_requirement, K->extensions)
		Kits::add_extension_dependency(KV, req);
}

@<Add build edges to the binaries for each architecture@> =
	inter_architecture *A;
	LOOP_OVER(A, inter_architecture) {
		build_vertex *BV = Graphs::file_vertex(Architectures::canonical_binary(P, A));
		Graphs::need_this_to_build(KV, BV);
		BuildSteps::attach(BV, build_kit_using_inter_skill, FALSE, NULL, A, K->as_copy);
		ADD_TO_LINKED_LIST(BV, build_vertex, BVL);
	}

@<Add build edges from the binary vertices to the contents vertex@> =
	build_vertex *BV;
	LOOP_OVER_LINKED_LIST(BV, build_vertex, BVL)
		Graphs::need_this_to_build(BV, CV);

@<Add build edges from the binary vertices to each section vertex@> =
	chapter_md *Cm;
	LOOP_OVER_LINKED_LIST(Cm, chapter_md, Wm->chapters_md) {
		section_md *Sm;
		LOOP_OVER_LINKED_LIST(Sm, section_md, Cm->sections_md) {
			filename *SF = Sm->source_file_for_section;
			build_vertex *SV = Graphs::file_vertex(SF);
			build_vertex *BV;
			LOOP_OVER_LINKED_LIST(BV, build_vertex, BVL)
				Graphs::need_this_to_build(BV, SV);
		}
	}

@ Suppose our kit wants to include Locksmith by Emily Short. If that's an
extension we have already read in, we can place a use edge to its existing
build vertex. If not, the best we can do is a use edge to a requirement
vertex, i.e., to a vertex meaning "we would like Locksmith but can't find it".

=
void Kits::add_extension_dependency(build_vertex *KV, inbuild_requirement *req) {
	build_vertex *RV = NULL;
	inform_extension *E;
	LOOP_OVER(E, inform_extension)
		if (Requirements::meets(E->as_copy->edition, req)) {
			RV = E->as_copy->vertex;
			build_vertex *V;
			int N = 0;
			LOOP_OVER_LINKED_LIST(V, build_vertex, KV->use_edges) {
				if ((V->type == REQUIREMENT_VERTEX) &&
					(Requirements::meets(E->as_copy->edition, V->as_requirement))) {
					LinkedLists::delete(N, KV->use_edges);
					break;
				}
				N++;
			}
			break;
		}
	if (RV == NULL) {
		build_vertex *V;
		int N = 0;
		LOOP_OVER_LINKED_LIST(V, build_vertex, KV->use_edges) {
			if ((V->type == REQUIREMENT_VERTEX) &&
				(Requirements::trumps(req, V->as_requirement))) {
				LinkedLists::delete(N, KV->use_edges);
				break;
			}
			N++;
		}
		RV = Graphs::req_vertex(req);
	}
	Graphs::need_this_to_use(KV, RV);
}
