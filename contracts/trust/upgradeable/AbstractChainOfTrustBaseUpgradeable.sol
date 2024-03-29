// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../common/upgradeable/BaseRelayRecipientUpgradeable.sol";
import "../IChainOfTrustBase.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract AbstractChainOfTrustBaseUpgradeable is
    BaseRelayRecipientUpgradeable,
    OwnableUpgradeable,
    IChainOfTrustBase
{
    // #################################################################
    uint16 public constant version = 1;
    uint256 public memberCounter;
    // entityManager => (gId, did)
    mapping(address => groupDetail) public group;
    // gId => entityManager
    mapping(uint256 => address) public manager;

    // gIdParent => gIdMember  => groupMemberDetail
    mapping(uint256 => mapping(uint256 => MemberDetail)) public trustedList;

    mapping(uint256 => uint256) public trustedBy;

    uint8 public depth;
    uint8 public revokeConfigMode;
    bool public isRootMaintainer;
    uint8 public constant ROOTANDPARENT = 1;
    uint8 public constant ALLANCESTORS = 2;

    uint256 public prevBlock;

    function updateMaintainerMode(bool rootMaintainer) external onlyOwner {
        require(isRootMaintainer != rootMaintainer, "ISC");
        isRootMaintainer = rootMaintainer;
        emit MaintainerModeChanged(isRootMaintainer, prevBlock);
        _emitContractBlockChangeIfNeeded();
    }

    function updateDepth(uint8 chainDepth) external {
        _validateMaintainer();
        uint8 prevDepth = depth;
        depth = chainDepth;
        emit DepthChanged(prevDepth, depth, prevBlock);
        _emitContractBlockChangeIfNeeded();
    }

    function _emitContractBlockChangeIfNeeded() private {
        if (prevBlock == block.number) return;
        emit ContractChange(prevBlock);
        prevBlock = block.number;
    }

    function updateRevokeMode(uint8 revokeMode) external {
        _validateMaintainer();
        uint8 prevRevokeMode = revokeConfigMode;
        revokeConfigMode = revokeMode;
        emit RevokeModeChanged(prevRevokeMode, revokeMode, prevBlock);
        _emitContractBlockChangeIfNeeded();
    }

    function updateDid(string memory did) external {
        address memberAddress = _msgSender();
        groupDetail storage detail = group[memberAddress];
        require(_checkChainOfTrustByExpiration(detail.gId), "MIRC");
        detail.did = did;
        emit DidChanged(memberAddress, did, prevBlock);
        _emitContractBlockChangeIfNeeded();
    }

    function transferRoot(address newRootManager, string memory did) external {
        address executor = _msgSender();
        address rootManager = manager[1];
        require((executor == rootManager || executor == owner()), "NA");
        groupDetail storage newGroup = group[newRootManager];
        require(newGroup.gId == 0, "MAEx"); // means the new root manager candidate shouldn't exit.
        manager[1] = newRootManager;
        groupDetail storage t = group[rootManager];
        newGroup.gId = t.gId;
        newGroup.did = did;
        t.did = "";
        t.gId = 0;
        emit RootManagerUpdated(executor, rootManager, newRootManager);
        _emitContractBlockChangeIfNeeded();
    }

    function _configMember(
        uint256 gId,
        string memory did,
        address entityManager
    ) private {
        groupDetail storage gd = group[entityManager];
        gd.gId = gId;
        manager[gId] = entityManager;
        gd.did = did;
        emit DidChanged(entityManager, did, prevBlock);
    }

    function addOrUpdateGroupMember(
        address memberEntity,
        string memory did,
        uint256 period
    ) external {
        address parentEntity = _msgSender();
        uint256 exp = _getExp(period);
        _addOrUpdateGroupMember(parentEntity, memberEntity, did, exp);
    }

    function revokeMember(address memberEntity, string memory did) external {
        address parentEntity = _msgSender();
        _revokeMember(parentEntity, parentEntity, memberEntity, did);
    }

    function revokeMemberByRoot(
        address memberEntity,
        string memory did
    ) external {
        _revokeMemberByRoot(memberEntity, did, _msgSender());
    }

    function revokeMemberByAnyAncestor(
        address memberEntity,
        string memory did
    ) external {
        _revokeMemberByAnyAncestor(_msgSender(), memberEntity, did);
    }

    function _revokeMemberByRoot(
        address memberEntity,
        string memory did,
        address actor
    ) internal {
        require(revokeConfigMode == ROOTANDPARENT, "RBRNE");
        require(group[actor].gId == 1, "OR");
        _revokeMemberIndirectly(actor, memberEntity, did);
    }

    function _revokeMemberByAnyAncestor(
        address ancestor,
        address memberEntity,
        string memory did
    ) internal {
        require(revokeConfigMode == ALLANCESTORS, "RBAANE");
        _revokeMemberIndirectly(ancestor, memberEntity, did);
    }

    function _revokeMemberIndirectly(
        address actor,
        address memberEntity,
        string memory did
    ) private {
        uint256 memberEntityGId = group[memberEntity].gId;
        uint256 parentEntityGId = trustedBy[memberEntityGId];
        require(parentEntityGId > 0, "MNA"); // means "memberEntity" was not added to any group, indirectly makes sure  memberEntityGId > 1
        address parentEntity = manager[parentEntityGId];
        uint256 actorGId = group[actor].gId;

        require(_checkAncestor(actorGId, memberEntityGId), "NA"); // validates also the particular chain is valid (e.g. not expired)
        _revokeMember(actor, parentEntity, memberEntity, did);
    }

    function _revokeMember(
        address revokerEntity,
        address parentEntity,
        address memberEntity,
        string memory did
    ) internal {
        uint256 parentGId = group[parentEntity].gId;
        uint256 memberGId = group[memberEntity].gId;
        MemberDetail storage d = trustedList[parentGId][memberGId];
        uint256 currentTime = block.timestamp;
        require(d.exp > currentTime, "MAE");
        _validateDidMatch(did, memberEntity);
        d.exp = currentTime;
        emit GroupMemberRevoked(
            revokerEntity,
            parentEntity,
            memberEntity,
            did,
            currentTime,
            prevBlock
        );
        _emitContractBlockChangeIfNeeded();
    }

    function _getTimestamp() private view returns (uint256 timestamp) {
        timestamp = block.timestamp;
    }

    function _getExp(uint256 period) internal view returns (uint256 exp) {
        uint256 currentTime = _getTimestamp();
        require(type(uint256).max - currentTime >= period, "IP");
        exp = currentTime + period;
    }

    function _addOrUpdateGroupMember(
        address parentEntity,
        address memberEntity,
        string memory memberDid,
        uint256 exp
    ) internal {
        groupDetail memory g = group[memberEntity];
        uint256 memberGId;
        uint256 parentGId = group[parentEntity].gId;
        if (g.gId > 0) {
            _checkParentOrThrow(g.gId, parentGId);
            memberGId = g.gId;
            _validateDidMatch(memberDid, memberEntity);
        } else {
            memberCounter++;
            memberGId = memberCounter;
            _configMember(memberGId, memberDid, memberEntity);
        }
        require(parentGId > 0, "NA");
        _verifyWhetherAChildCanBeAdded(parentGId, depth);

        uint256 iat = _getTimestamp();

        MemberDetail storage t = trustedList[parentGId][memberGId];
        // require(t.iat == uint256(0), "TLAA"); // todo: check
        trustedBy[memberGId] = parentGId;
        t.iat = iat;
        t.exp = exp;
        emit GroupMemberChanged(
            parentEntity,
            memberEntity,
            memberDid,
            iat,
            exp,
            prevBlock
        );
        _emitContractBlockChangeIfNeeded();
    }

    function _validateDidMatch(
        string memory memberDid,
        address memberEntity
    ) private view {
        require(
            _computeAddress(memberDid) ==
                _computeAddress(group[memberEntity].did),
            "DDM"
        );
    }

    function _checkParentOrThrow(
        uint256 memberGId,
        uint256 parentCandidateGId
    ) private view {
        uint256 parentGId = trustedBy[memberGId];
        if (!_checkChainOfTrustByExpiration(parentGId)) return; // if chain is broken by expiration then allow adding some child of that chain
        if (parentGId == parentCandidateGId) return;
        _checkParentIsExpired(parentGId, memberGId);
    }

    function _checkParentIsExpired(
        uint256 parentGId,
        uint256 memberGId
    ) private view {
        require(trustedList[parentGId][memberGId].exp < block.timestamp, "MAA");
    }

    function _computeAddress(
        string memory txt
    ) private pure returns (address addr) {
        bytes32 h = keccak256(abi.encode((txt)));
        assembly {
            addr := h
        }
    }

    function _verifyWhetherAChildCanBeAdded(
        uint256 parentGId,
        uint8 d
    ) private view {
        require(d > 0, "DOOT");
        if (parentGId == 1) {
            return;
        }
        uint256 grandParentGId = trustedBy[parentGId];
        require(
            trustedList[grandParentGId][parentGId].exp > block.timestamp,
            "NA"
        );
        return _verifyWhetherAChildCanBeAdded(grandParentGId, d - 1);
    }

    function _validateMember(
        uint256 memberGId,
        uint8 d
    ) private view returns (bool isValid) {
        if (d == 0) return false;
        if (memberGId == 1) {
            return true;
        }
        uint256 parentGId = trustedBy[memberGId];
        if (trustedList[parentGId][memberGId].exp < block.timestamp) {
            return false;
        }
        return _validateMember(parentGId, d - 1);
    }

    function _checkChainOfTrustByExpiration(
        uint256 memberGId
    ) private view returns (bool isValid) {
        if (memberGId == 1) {
            // because of the hierarchy of chain of trust, code will eventually reach here
            return true;
        }
        uint256 parentGId = trustedBy[memberGId];
        if (trustedList[parentGId][memberGId].exp < block.timestamp)
            return false;
        return _checkChainOfTrustByExpiration(parentGId); // (grandParentGId, d - 1);
    }

    function _checkAncestor(
        uint256 actorGId,
        uint256 memberGId
    ) private view returns (bool) {
        if (memberGId == 1) return false;
        uint256 parentGId = trustedBy[memberGId];
        require(trustedList[parentGId][memberGId].exp > block.timestamp, "RC");
        if (parentGId == actorGId) return true;
        return _checkAncestor(actorGId, parentGId);
    }

    function _validateMaintainer() private view {
        if (isRootMaintainer) {
            require(group[_msgSender()].gId == 1, "NA");
            return;
        }

        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function getMemberDetailsByEntityManager(
        address memberEntityManager
    ) external view returns (MemberProfile memory member) {
        uint256 memberGId = group[memberEntityManager].gId;
        member.gId = memberGId;
        member.did = group[memberEntityManager].did;
        if (memberGId == 1) {
            member.isValid = true;
            return member;
        }
        uint256 parentGId = trustedBy[memberGId];
        MemberDetail memory mDetail = trustedList[parentGId][memberGId];
        member.trustedBy = manager[parentGId];
        member.exp = mDetail.exp;
        member.iat = mDetail.iat;
        member.isValid = _validateMember(memberGId, depth + 1); // depth + 1 since actually root is one level even though it is level "0"
    }

    // #################################################################

    function __AbstractChainOfTrustBaseUpgradeable_init(
        address trustedForwarderAddress,
        uint8 chainDepth,
        string memory did,
        address rootEntityManager,
        uint8 revokeMode,
        bool rootMaintainer
    ) internal onlyInitializing {
        depth = chainDepth;
        memberCounter++;
        revokeConfigMode = revokeMode;
        _configMember(memberCounter, did, rootEntityManager);
        isRootMaintainer = rootMaintainer;
        _emitContractBlockChangeIfNeeded();
        __AbstractChainOfTrustBaseUpgradeable_init_unchained(
            trustedForwarderAddress
        );
    }

    function __AbstractChainOfTrustBaseUpgradeable_init_unchained(
        address trustedForwarderAddress
    ) internal onlyInitializing {
        __BaseRelayRecipient_init(trustedForwarderAddress);
        __Ownable_init();
    }

    /**
     * return the sender of this call.
     * if the call came through our Relay Hub, return the original sender.
     * should be used in the contract anywhere instead of msg.sender
     */
    function _msgSender()
        internal
        view
        virtual
        override(BaseRelayRecipientUpgradeable, ContextUpgradeable)
        returns (address sender)
    {
        bytes memory bytesSender;
        bool success;
        (success, bytesSender) = trustedForwarder.staticcall(
            abi.encodeWithSignature("getMsgSender()")
        );

        require(success, "SCF");

        return abi.decode(bytesSender, (address));
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}
