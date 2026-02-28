#include "../vendor/src/oniguruma.h"

__attribute__((constructor)) static void setup ()
{
	onig_init();
	onig_set_default_syntax(ONIG_SYNTAX_RUBY);
}
