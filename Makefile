.DEFAULT_GOAL := compiler
.PHONY: parser compiler docs

parser: src/Lex.hs src/Parse.hs

src/Parse.hs: src/Parse.y src/Syntax/Untyped.hs
	happy src/Parse.y

src/Lex.hs: src/Lex.x
	alex src/Lex.x

# builds the rest of the haskell files (compiler)
bin/act: src/*.hs src/*/*.hs
	cd src && cabal v2-install --installdir=../bin --overwrite-policy=always && cd ..

repl: src/Lex.hs src/Parse.hs
	cd src && cabal v2-repl

compiler: bin/act

docs:
	cd doc && mdbook build

docs-serve:
	cd doc && mdbook serve

frontend_pass=$(wildcard tests/frontend/pass/*/*.act)
frontend_fail=$(wildcard tests/frontend/fail/*/*.act)

parser_pass=$(frontend_pass)
typing_pass=$(filter-out $(failing_typing), $(parser_pass))
# supposed to fail
typing_fail=$(frontend_fail)
parser_fail=$(filter-out $(typing_fail), $(frontend_fail))

invariant_specs=$(wildcard tests/invariants/*/*.act)
invariant_pass=$(filter-out $(invariant_buggy), $(wildcard tests/invariants/pass/*.act) $(typing_pass))
invariant_fail=$(wildcard tests/invariants/fail/*.act)
invariant_buggy=tests/invariants/pass/amm-full.act

postcondition_specs=$(wildcard tests/postconditions/*/*.act)
postcondition_pass=$(wildcard tests/postconditions/pass/*.act) $(typing_pass)
postcondition_fail=$(wildcard tests/postconditions/fail/*.act)

# supposed to pass, but timeout
hevm_buggy=tests/hevm/pass/transfer/transfer.act tests/hevm/pass/simple/simple.act
# supposed to pass
hevm_pass=$(filter-out $(hevm_buggy), $(wildcard tests/hevm/pass/*/*.act))
# supposed to fail
hevm_fail=$(wildcard tests/hevm/fail/*/*.act)

# supposed to pass
failing_typing=tests/frontend/pass/array/array.act tests/frontend/pass/dss/vat.act tests/frontend/pass/creation/createMultiple.act tests/frontend/pass/staticstore/staticstore.act


coq-examples = tests/coq/transitions tests/coq/safemath tests/coq/exponent tests/coq/token tests/coq/ERC20 tests/coq/multi

.PHONY: test-coq $(coq-examples)
test-coq: compiler $(coq-examples)
$(coq-examples):
	make -C $@ clean
	make -C $@

test-parse: parser compiler $(parser_pass:=.parse.pass) $(parser_fail:=.parse.fail)
test-type: parser compiler $(typing_pass:=.type.pass) $(typing_fail:=.type.fail)
test-invariant: parser compiler $(invariant_pass:=.invariant.pass) $(invariant_fail:=.invariant.fail)
test-postcondition: parser compiler $(postcondition_pass:=.postcondition.pass) $(postcondition_fail:=.postcondition.fail)
test-hevm: parser compiler $(hevm_pass:=.hevm.pass) $(hevm_fail:=.hevm.fail)
test-cabal: src/*.hs
	cd src && cabal v2-run test

# Just checks parsing
tests/%.parse.pass:
	./bin/act parse --file tests/$* > tests/$*.parsed.hs.out
	diff tests/$*.parsed.hs.out tests/$*.parsed.hs
	rm tests/$*.parsed.hs.out

tests/%.parse.fail:
	./bin/act parse --file tests/$* && exit 1 || echo 0

tests/%.type.pass:
	./bin/act type --file tests/$* | jq . > tests/$*.typed.json.out
	diff tests/$*.typed.json.out tests/$*.typed.json
	rm tests/$*.typed.json.out

tests/%.type.fail:
	./bin/act type --file tests/$* && exit 1 || echo 0

tests/%.invariant.pass:
	./bin/act prove --file tests/$*
	./bin/act prove --solver cvc5 --file tests/$*

tests/%.invariant.fail:
	./bin/act prove --file tests/$* && exit 1 || echo 0
	./bin/act prove --solver cvc5 --file tests/$* && exit 1 || echo 0

tests/%.postcondition.pass:
	./bin/act prove --file tests/$*
	./bin/act prove --solver cvc5 --file tests/$*

tests/%.postcondition.fail:
	./bin/act prove --file tests/$* && exit 1 || echo 0
	./bin/act prove --solver cvc5 --file tests/$* && exit 1 || echo 0

tests/hevm/pass/%.act.hevm.pass:
	$(eval CONTRACT := $(shell awk '/contract/{ print $$2 }' tests/hevm/pass/$*.sol))
	./bin/act hevm --spec tests/hevm/pass/$*.act --sol tests/hevm/pass/$*.sol --contract $(CONTRACT)

tests/hevm/fail/%.act.hevm.fail:
	$(eval CONTRACT := $(shell awk '/contract/{ print $$2 }' tests/hevm/fail/$*.sol))
	./bin/act hevm --spec tests/hevm/fail/$*.act --sol tests/hevm/fail/$*.sol --contract $(CONTRACT) && exit 1 || echo 0

test-ci: test-parse test-type test-invariant test-postcondition test-coq test-hevm
test: test-ci test-cabal
