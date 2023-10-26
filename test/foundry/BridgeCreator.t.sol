// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./util/TestUtil.sol";
import "../../src/rollup/BridgeCreator.sol";
import "../../src/bridge/ISequencerInbox.sol";
import "../../src/bridge/AbsInbox.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract BridgeCreatorTest is Test {
    BridgeCreator public creator;
    address public owner = address(100);
    uint256 public constant MAX_DATA_SIZE = 117_964;
    IDataHashReader dummyDataHashReader = IDataHashReader(address(137));
    IBlobBasefeeReader dummyBlobBasefeeReader = IBlobBasefeeReader(address(138));

    BridgeCreator.BridgeTemplates ethBasedTemplates =
        BridgeCreator.BridgeTemplates({
            bridge: new Bridge(),
            inbox: new Inbox(MAX_DATA_SIZE),
            rollupEventInbox: new RollupEventInbox(),
            outbox: new Outbox()
        });
    BridgeCreator.BridgeTemplates erc20BasedTemplates =
        BridgeCreator.BridgeTemplates({
            bridge: new ERC20Bridge(),
            inbox: new ERC20Inbox(MAX_DATA_SIZE),
            rollupEventInbox: new ERC20RollupEventInbox(),
            outbox: new ERC20Outbox()
        });

    function setUp() public {
        vm.prank(owner);
        creator = new BridgeCreator(ethBasedTemplates, erc20BasedTemplates);
    }

    function getEthBasedTemplates() internal returns (BridgeCreator.BridgeTemplates memory) {
        BridgeCreator.BridgeTemplates memory templates;
        (templates.bridge, templates.inbox, templates.rollupEventInbox, templates.outbox) = creator
            .ethBasedTemplates();
        return templates;
    }

    function getErc20BasedTemplates() internal returns (BridgeCreator.BridgeTemplates memory) {
        BridgeCreator.BridgeTemplates memory templates;
        (templates.bridge, templates.inbox, templates.rollupEventInbox, templates.outbox) = creator
            .erc20BasedTemplates();
        return templates;
    }

    function assertEq(
        BridgeCreator.BridgeTemplates memory a,
        BridgeCreator.BridgeTemplates memory b
    ) internal {
        assertEq(address(a.bridge), address(b.bridge), "Invalid bridge");
        assertEq(address(a.inbox), address(b.inbox), "Invalid inbox");
        assertEq(
            address(a.rollupEventInbox),
            address(b.rollupEventInbox),
            "Invalid rollup event inbox"
        );
        assertEq(address(a.outbox), address(b.outbox), "Invalid outbox");
    }

    function assertEq(
        BridgeCreator.BridgeContracts memory a,
        BridgeCreator.BridgeContracts memory b
    ) internal {
        assertEq(address(a.bridge), address(b.bridge), "Invalid bridge");
        assertEq(address(a.sequencerInbox), address(b.sequencerInbox), "Invalid seqInbox");
        assertEq(address(a.inbox), address(b.inbox), "Invalid inbox");
        assertEq(
            address(a.rollupEventInbox),
            address(b.rollupEventInbox),
            "Invalid rollup event inbox"
        );
        assertEq(address(a.outbox), address(b.outbox), "Invalid outbox");
    }

    /* solhint-disable func-name-mixedcase */
    function test_constructor() public {
        assertEq(getEthBasedTemplates(), ethBasedTemplates);
        assertEq(getErc20BasedTemplates(), erc20BasedTemplates);
    }

    function test_updateTemplates() public {
        BridgeCreator.BridgeTemplates memory templs = BridgeCreator.BridgeTemplates({
            bridge: Bridge(address(200)),
            inbox: Inbox(address(202)),
            rollupEventInbox: RollupEventInbox(address(203)),
            outbox: Outbox(address(204))
        });

        vm.prank(owner);
        creator.updateTemplates(templs);

        assertEq(getEthBasedTemplates(), templs);
    }

    function test_updateERC20Templates() public {
        BridgeCreator.BridgeTemplates memory templs = BridgeCreator.BridgeTemplates({
            bridge: ERC20Bridge(address(400)),
            inbox: ERC20Inbox(address(402)),
            rollupEventInbox: ERC20RollupEventInbox(address(403)),
            outbox: ERC20Outbox(address(404))
        });

        vm.prank(owner);
        creator.updateERC20Templates(templs);

        assertEq(getErc20BasedTemplates(), templs);
    }

    function test_createEthBridge() public {
        address proxyAdmin = address(300);
        address rollup = address(301);
        address nativeToken = address(0);
        ISequencerInbox.MaxTimeVariation memory timeVars = ISequencerInbox.MaxTimeVariation(
            10,
            20,
            30,
            40
        );
        BridgeCreator.BridgeContracts memory contracts = creator.createBridge(
            proxyAdmin,
            rollup,
            nativeToken,
            timeVars,
            MAX_DATA_SIZE,
            dummyDataHashReader,
            dummyBlobBasefeeReader
        );
        (
            IBridge bridge,
            ISequencerInbox seqInbox,
            IInboxBase inbox,
            IRollupEventInbox eventInbox,
            IOutbox outbox
        ) = (
                contracts.bridge,
                contracts.sequencerInbox,
                contracts.inbox,
                contracts.rollupEventInbox,
                contracts.outbox
            );

        // bridge
        assertEq(address(bridge.rollup()), rollup, "Invalid bridge rollup ref");
        assertEq(bridge.activeOutbox(), address(0), "Invalid activeOutbox ref");

        // seqInbox
        assertEq(address(seqInbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(seqInbox.rollup()), rollup, "Invalid seq rollup ref");
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation = seqInbox.maxTimeVariation();
        assertEq(maxTimeVariation.delayBlocks, timeVars.delayBlocks, "Invalid delayBlocks");
        assertEq(maxTimeVariation.futureBlocks, timeVars.futureBlocks, "Invalid futureBlocks");
        assertEq(maxTimeVariation.delaySeconds, timeVars.delaySeconds, "Invalid delaySeconds");
        assertEq(maxTimeVariation.futureSeconds, timeVars.futureSeconds, "Invalid futureSeconds");

        // inbox
        assertEq(address(inbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(inbox.sequencerInbox()), address(seqInbox), "Invalid seqInbox ref");
        assertEq(inbox.allowListEnabled(), false, "Invalid allowListEnabled");
        assertEq(AbsInbox(address(inbox)).paused(), false, "Invalid paused status");

        // rollup event inbox
        assertEq(address(eventInbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(eventInbox.rollup()), rollup, "Invalid event inbox rollup ref");

        // outbox
        assertEq(address(outbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(outbox.rollup()), rollup, "Invalid outbox rollup ref");

        // revert fetching native token
        vm.expectRevert();
        IERC20Bridge(address(bridge)).nativeToken();
    }

    function test_createERC20Bridge() public {
        address proxyAdmin = address(300);
        address rollup = address(301);
        address nativeToken = address(
            new ERC20PresetFixedSupply("Appchain Token", "App", 1_000_000, address(this))
        );
        ISequencerInbox.MaxTimeVariation memory timeVars = ISequencerInbox.MaxTimeVariation(
            10,
            20,
            30,
            40
        );
        BridgeCreator.BridgeContracts memory contracts = creator.createBridge(
            proxyAdmin,
            rollup,
            nativeToken,
            timeVars,
            MAX_DATA_SIZE,
            dummyDataHashReader,
            dummyBlobBasefeeReader
        );
        (
            IBridge bridge,
            ISequencerInbox seqInbox,
            IInboxBase inbox,
            IRollupEventInbox eventInbox,
            IOutbox outbox
        ) = (
                contracts.bridge,
                contracts.sequencerInbox,
                contracts.inbox,
                contracts.rollupEventInbox,
                contracts.outbox
            );

        // bridge
        assertEq(address(bridge.rollup()), rollup, "Invalid bridge rollup ref");
        assertEq(
            address(IERC20Bridge(address(bridge)).nativeToken()),
            nativeToken,
            "Invalid nativeToken ref"
        );
        assertEq(bridge.activeOutbox(), address(0), "Invalid activeOutbox ref");

        // seqInbox
        assertEq(address(seqInbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(seqInbox.rollup()), rollup, "Invalid seq inbox rollup ref");
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation = seqInbox.maxTimeVariation();
        assertEq(maxTimeVariation.delayBlocks, timeVars.delayBlocks, "Invalid delayBlocks");
        assertEq(maxTimeVariation.futureBlocks, timeVars.futureBlocks, "Invalid futureBlocks");
        assertEq(maxTimeVariation.delaySeconds, timeVars.delaySeconds, "Invalid delaySeconds");
        assertEq(maxTimeVariation.futureSeconds, timeVars.futureSeconds, "Invalid futureSeconds");

        // inbox
        assertEq(address(inbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(inbox.sequencerInbox()), address(seqInbox), "Invalid seqInbox ref");
        assertEq(inbox.allowListEnabled(), false, "Invalid allowListEnabled");
        assertEq(AbsInbox(address(inbox)).paused(), false, "Invalid paused status");

        // rollup event inbox
        assertEq(address(eventInbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(eventInbox.rollup()), rollup, "Invalid event inbox rollup ref");

        // outbox
        assertEq(address(outbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(outbox.rollup()), rollup, "Invalid outbox rollup ref");
    }
}
