'use strict';
// Probe classes ported from the production feature-proof review and Core #345.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const {deriveFeatures,detect} = require('./lib/rs-capability.cjs');
const {instructions} = require('./lib/dockerfile-rs-features.cjs');
const actual=fs.readFileSync(path.join(__dirname,'fixtures/rs-capability/production.Dockerfile'),'utf8');
const minimal='[features]\nrust-reasoning-settings=[]\nrust-routing-mode=[]\n';
const cargo=minimal+'default=["default-only"]\ndefault-only=[]\n';
const BUILD='cargo build --release --locked -p noevia-server --features rust-reasoning-settings,rust-routing-mode';
const df=({build=BUILD,extra='',runtimeExtra='',copy='COPY --from=front /out/ /usr/local/bin/',tail='FROM runtime AS production'}={})=>[
 'FROM rust:1.99-slim-bookworm AS front','ENV RUSTUP_TOOLCHAIN=1.99.0 CARGO_TERM_COLOR=never','COPY rs/ /src/','WORKDIR /src',
 `RUN mkdir -p /out && ${build} && cp target/release/noevia-server /out/noevia-server`,extra,
 'FROM node:22-bookworm AS runtime','WORKDIR /app',copy,runtimeExtra,tail,''].join('\n');
let count=0;
function check(name,text,expected,manifest=cargo) {
 const got=deriveFeatures(text,manifest);
 try { if(expected===null) assert.equal(got,null); else { assert.ok(got instanceof Set); for(const f of expected.yes||[])assert.ok(got.has(f),f); for(const f of expected.no||[])assert.ok(!got.has(f),f); } }
 catch(e){throw new Error(name+': '+e.message);}
 count++;
}
check('plain literal build',df(),{yes:['rust-reasoning-settings','default-only']});
check('active comment/continuation',df({build:'cargo  build --release \\\n # --features imaginary\n -p noevia-server \\\n --features rust-routing-mode'}),{yes:['rust-routing-mode','default-only'],no:['imaginary','rust-reasoning-settings']});
check('no-feature build uses only defaults',df({build:'cargo build --release -p noevia-server'}),{yes:['default-only'],no:['rust-routing-mode']});
check('no defaults uses only listed features',df({build:'cargo build --release --package=noevia-server --bin noevia-server -F noevia-server/rust-routing-mode --no-default-features'}),{yes:['rust-routing-mode'],no:['default','default-only','rust-reasoning-settings']});
check('absent default never invented',df(),{no:['default']},minimal);
check('explicit empty default exists',df(),{yes:['default'],no:['default-only']},minimal+'default=[]\n');
for(const extra of [
 'RUN cargo build --release -p noevia-server --no-default-features',
 'RUN cargo  build --release -p noevia-server --features rust-routing-mode',
 'RUN cargo\tbuild --release -p noevia-server',
 'RUN cargo build --release',
 'RUN cargo install --path bins/noevia-server',
 'COPY patched /src/target/release/noevia-server',
 'COPY rogue /out/', 'RUN rm /out/noevia-server','SHELL ["/bin/bash","-c"]','ONBUILD RUN true'
])check('extra producer or rewrite '+extra,df({extra}),null);
for(const build of [
 BUILD+'; cargo  build --release -p noevia-server --no-default-features',
 BUILD+' && cargo\tbuild --release -p noevia-server',
 BUILD+' && cp /legacy/noevia-server target/release/noevia-server',
 'cargo build --release -p noevia-server --features ${FRONT_FEATURES}',
 'cargo build --release -p noevia-server --features rust-routing-mode,${FRONT_FEATURES}',
 'cargo build --release -p noevia-server --features "rust-routing-mode,$FRONT_FEATURES"',
 'cargo build --release -p noevia-server --features `echo rust-routing-mode`',
 'cargo build --release -p noevia-server --features rust-*',
 'cargo build --release=true -p noevia-server',
 'cargo build --release -p noevia-server --no-default-features=true',
 'cargo build --release -p noevia-server --target x86_64-unknown-linux-musl',
 'cargo build --release --workspace', 'cargo build --release -p noevia-server --all-features',
 'cargo +nightly build --release -p noevia-server','cargo xtask build',
 'cargo build --release','cargo install --path bins/noevia-server',
 'sh -c "'+BUILD+'"','make build','false || '+BUILD, '('+BUILD+')',
 'if true; then '+BUILD+'; fi',BUILD+' || true',BUILD+' &','true; '+BUILD,
 BUILD+' > target/release/noevia-server'
])check('unsupported build '+build,df({build}),null);
for(const runtimeExtra of [
 'COPY --from=front /out/ /usr/local/bin/','ADD rogue /usr/local/bin/',
 'COPY rogue /usr/local/','RUN cp /bin/true /usr/local/bin/noevia-server',
 'RUN ln -sf /bin/true /usr/local/bin/noevia-server','ONBUILD COPY x y','SHELL ["/bin/sh","-c"]'
])check('runtime overwrite '+runtimeExtra,df({runtimeExtra}),null);
for(const copy of [
 'COPY --from=legacy-builder /out/ /usr/local/bin/',
 'COPY --from=0 /out/ /usr/local/bin/',
 'COPY /out/noevia-server /usr/local/bin/noevia-server',
 'COPY --from=front /legacy/noevia-server /usr/local/bin/noevia-server',
 'COPY --from=front /out/other /usr/local/bin/noevia-server',
 'COPY --from=${BUILDER} /out/ /usr/local/bin/'
])check('unproven copy '+copy,df({copy}),null);
check('final stage does not inherit runtime',df({tail:'FROM node:22-bookworm AS production'}),null);
check('unresolved final base',df({tail:'FROM ${RUNTIME} AS production'}),null);
check('unknown front base',df().replace('FROM rust:1.99-slim-bookworm AS front','FROM ${FRONT_BASE} AS front'),null);
check('unresolved platform',df().replace('FROM rust:','FROM --platform=$PLATFORM rust:'),null);
check('renamed source',df().replace('AS front','AS renamed'),null);
check('escape directive','# escape=`\n'+df(),null);
check('unfinished continuation',df()+'RUN true \\',null);
check('ancestor rebuild',df().replace('FROM node:22-bookworm AS runtime','FROM front AS copied\nRUN cargo build --release -p noevia-server\nFROM node:22-bookworm AS runtime').replace('COPY --from=front','COPY --from=copied'),null);
check('inherited producer without rebuild',df().replace('FROM node:22-bookworm AS runtime','FROM front AS copied\nFROM node:22-bookworm AS runtime').replace('COPY --from=front','COPY --from=copied'),{yes:['rust-routing-mode']});
check('commented enabled build is not evidence',df({build:'cargo build --release -p noevia-server --no-default-features'}).replace('RUN mkdir','# RUN '+BUILD+'\nRUN mkdir'),{no:['rust-routing-mode','default']});
check('unused valid copy does not prove runtime',df({copy:'COPY --from=legacy-builder /out/ /usr/local/bin/',tail:'FROM node:22-bookworm AS unused\nCOPY --from=front /out/ /usr/local/bin/\nFROM runtime AS production'}),null);
check('actual output replacement',actual.replace('cp target/release/noevia-server /out/noevia-server;','cp /legacy/noevia-server /out/noevia-server;'),null,minimal);
check('actual whitespace second build',actual.replace('cp target/release/noevia-server','cargo  build --release --locked -p noevia-server --features rust-routing-mode; cp target/release/noevia-server'),null,minimal);
check('actual runtime legacy copy while build-stage copy survives',actual.replace('COPY --from=front /out/ /usr/local/bin/','COPY --from=legacy-builder /out/ /usr/local/bin/'),null,minimal);
const legacyStage = ['FROM rust:1.99-slim-bookworm AS legacy-builder','ENV RUSTUP_TOOLCHAIN=1.99.0 CARGO_TERM_COLOR=never','COPY rs/ /src/','WORKDIR /src','RUN mkdir -p /out && cargo build --release -p noevia-server --no-default-features --features rust-routing-mode && cp target/release/noevia-server /out/noevia-server',''].join('\n');
check('trace a real alternate producer rather than unused evidence', df({copy:'COPY --from=legacy-builder /out/ /usr/local/bin/',tail:'FROM node:22-bookworm AS unused\nCOPY --from=front /out/ /usr/local/bin/\nFROM runtime AS production'}).replace('FROM node:22-bookworm AS runtime',legacyStage+'FROM node:22-bookworm AS runtime'),{yes:['rust-routing-mode'],no:['rust-reasoning-settings','default-only']});
assert.equal(instructions('# RUN bogus\nRUN cargo \\\n# continued comment\n build')[0].args,'cargo  build');
const absentDefault=deriveFeatures(df(),minimal);
assert.equal(detect('pub const FEATURES: &[&str] = &[#[cfg(feature = "default")] "cap"];','FEATURES','cap',absentDefault),'legacy');
console.log(`Shipped binary feature proof: ${count+2} passed`);
