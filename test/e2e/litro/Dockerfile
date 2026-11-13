# Everything the litro test jobs need, baked on top of arbitrum-litro: Foundry, Node 24, the yarn
# packages, and develop's compiled contracts. test/e2e/litro/ci.bash runs one container from it, swaps
# in the checkout's source and compiles it there; hardhat and forge recompile only files whose content
# changed, so the tests always run the checkout's contracts.
#
#   docker build -f test/e2e/litro/Dockerfile -t ghcr.io/offchainlabs/nitro-contracts-litro-tests:develop .
FROM ghcr.io/foundry-rs/foundry:v1.9.0 AS foundry
FROM node:24-bookworm-slim AS node

FROM ghcr.io/offchainlabs/arbitrum-litro:v0.5.1-nc3.2-l2
LABEL org.opencontainers.image.source=https://github.com/OffchainLabs/nitro-contracts
# litro's L2 reads L1 every 15s by default, and an L3 assertion is confirmable only once the L2 has seen
# a newer L1 block, so each withdrawal waited up to 15s more.
ENV TESTNODE_PARENT_CHAIN_POLL_INTERVAL=250ms \
    ARBITRUM_TESTNODE_CONFIG_DIR=/opt/arbitrum-testnode/export-config
COPY --from=foundry /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/
# Tests run on Node 24 like the rest of CI; litro's own scripts keep the Node it ships.
COPY --from=node /usr/local/bin/node /opt/node24/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /opt/node24/lib/node_modules/npm
USER root
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /opt/node24/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /opt/node24/bin/npx
USER user

WORKDIR /home/user/nitro-contracts
COPY --chown=user:user package.json yarn.lock ./
COPY --chown=user:user patches patches
RUN export PATH=/opt/node24/bin:$PATH && yarn install --frozen-lockfile && yarn cache clean && \
    sha256sum package.json yarn.lock patches/* > /home/user/deps.sha256

COPY --chown=user:user . .
RUN export PATH=/opt/node24/bin:$PATH && yarn build && yarn build:forge:yul && test/e2e/litro/l3.bash build /tmp/l3
