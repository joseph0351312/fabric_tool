package main

import (
	"encoding/json"
	"fmt"
	"log"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type smartcontract struct {
	contractapi.Contract
}

type Transfer_verification_BCC struct {
	ID_VIN  string `json:"ID_VIN"`
	CID_TTP string `json:"CID_TTP"`
}

type Bidding_contractsign_BCC struct {
	ID_TRAN    string `json:"ID_TRAN"`
	ID_BR      string `json:"ID_BR"`
	P_BR       string `json:"P_BR"`
	TS_BR_UCAP string `json:"TS_BR_UCAP"`
	SIGN_BR    string `json:"SIGN_BR"`
	ID_UCAP    string `json:"ID_UCAP"`
	CID_UCAP   string `json:"CID_UCAP"`
	CID_BROR   string `json:"CID_BROR"`
}

// {---初始化定義
func (s *smartcontract) InitLedger(ctx contractapi.TransactionContextInterface) error {

	trans_ver_bbc := Transfer_verification_BCC{ID_VIN: " ", CID_TTP: " "}
	Json, err := json.Marshal(trans_ver_bbc)
	err = ctx.GetStub().PutState("00", Json)
	if err != nil {
		return fmt.Errorf("failed to put  state, %v", err)
	}

	bid_contra_bbc := Bidding_contractsign_BCC{ID_TRAN: "01", ID_BR: " ", P_BR: " ", TS_BR_UCAP: " ", SIGN_BR: " ", ID_UCAP: " ", CID_UCAP: " ", CID_BROR: " "}
	Json, err = json.Marshal(bid_contra_bbc)
	err = ctx.GetStub().PutState(bid_contra_bbc.ID_TRAN, Json)
	if err != nil {
		return fmt.Errorf("failed to put state, %v", err)
	}

	return nil
}

func (s *smartcontract) Delete(ctx contractapi.TransactionContextInterface, id string) error {
	return ctx.GetStub().DelState(id)
}

//---初始化定義}

// 車輛轉交驗證階段--------------------
// 創建
func (s *smartcontract) Create_transfer_verification_BCC(ctx contractapi.TransactionContextInterface, ID_VIN string) error {

	assetJSON, err := ctx.GetStub().GetState(ID_VIN)
	if err != nil {
		return err
	}
	if assetJSON != nil {
//		return fmt.Errorf("duplicated address", ID_VIN)
	}

	//把ID_VIN寫進去{
	trans_ver_bbc := Transfer_verification_BCC{ID_VIN: ID_VIN, CID_TTP: " "}
	Json, err := json.Marshal(trans_ver_bbc)
	if err != nil {
		return fmt.Errorf("Marshal", err)
	}

	return ctx.GetStub().PutState(ID_VIN, Json)
	//把ID_VIN寫進去}
}

// 車輛轉交驗證階段上傳
func (s *smartcontract) Update_transfer_BCC(ctx contractapi.TransactionContextInterface, id string, cid string) error {
	idjson, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read from world state: %v", err)
	}
	if idjson == nil {
		return fmt.Errorf("the batch %s does not exist", id)
	}

	var trans_ver_bbc Transfer_verification_BCC
	err = json.Unmarshal(idjson, &trans_ver_bbc)
	if err != nil {
		return err
	}
	fmt.Println(trans_ver_bbc.CID_TTP)
	//" "
	if trans_ver_bbc.CID_TTP != " " {
		return fmt.Errorf("")
	}
	trans_ver_bbc.CID_TTP = cid

	cidjson, err := json.Marshal(trans_ver_bbc)
	if err != nil {
		return fmt.Errorf("failed to marshal batch: %v", err)
	}
	return ctx.GetStub().PutState(cid, cidjson)
}

// 讀取
func (s *smartcontract) Read_transfer_verification_BCC(ctx contractapi.TransactionContextInterface, id string) (*Transfer_verification_BCC, error) {
	Json, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if Json == nil {
		return nil, fmt.Errorf("the app %s does not exist", id)
	}

	var trans_ver_bbc Transfer_verification_BCC
	err = json.Unmarshal(Json, &trans_ver_bbc)
	if err != nil {
		return nil, err
	}

	return &trans_ver_bbc, nil
}

//--------------------------------------

// 競標及合約簽訂階段--------------------
// 創建
func (s *smartcontract) Create_bidding_contractsign_BCC(ctx contractapi.TransactionContextInterface, ID_TRAN string, ID_BR string, P_BR string, TS_BR_UCAP string, SIGN_BR string) error {

	assetJSON, err := ctx.GetStub().GetState(ID_TRAN)
	if err != nil {
		return err
	}
	if assetJSON != nil {
		return fmt.Errorf("duplicated address", ID_TRAN)
	}

	bid_contra_bbc := Bidding_contractsign_BCC{ID_TRAN: ID_TRAN, ID_BR: ID_BR, P_BR: P_BR, TS_BR_UCAP: TS_BR_UCAP, SIGN_BR: SIGN_BR, CID_UCAP: " ", CID_BROR: " "}
	Json, err := json.Marshal(bid_contra_bbc)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(ID_TRAN, Json)
}

// 競標階段上傳
func (s *smartcontract) Update_bidding_BCC(ctx contractapi.TransactionContextInterface, id string, cid string) error {
	idjson, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read from world state: %v", err)
	}
	if idjson == nil {
		return fmt.Errorf("the batch %s does not exist", id)
	}

	var bid_contra_bbc Bidding_contractsign_BCC
	err = json.Unmarshal(idjson, &bid_contra_bbc)
	if err != nil {
		return err
	}
	fmt.Println(bid_contra_bbc.CID_UCAP)
	//" "
	if bid_contra_bbc.CID_UCAP != " " {
		return fmt.Errorf("")
	}
	bid_contra_bbc.CID_UCAP = cid

	cidjson, err := json.Marshal(bid_contra_bbc)
	if err != nil {
		return fmt.Errorf("failed to marshal batch: %v", err)
	}
	return ctx.GetStub().PutState(cid, cidjson)
}

//合約簽訂階段上傳
func (s *smartcontract) Update_contractsign_BCC(ctx contractapi.TransactionContextInterface, id string, cid string) error {
	idjson, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read from world state: %v", err)
	}
	if idjson == nil {
		return fmt.Errorf("the batch %s does not exist", id)
	}

	var bid_contra_bbc Bidding_contractsign_BCC
	err = json.Unmarshal(idjson, &bid_contra_bbc)
	if err != nil {
		return err
	}

	bid_contra_bbc.CID_BROR = cid
	cidjson, err := json.Marshal(bid_contra_bbc)
	if err != nil {
		return fmt.Errorf("failed to marshal batch: %v", err)
	}
	return ctx.GetStub().PutState(cid, cidjson)
}

// 讀取
func (s *smartcontract) Read_Bidding_contractsign_BCC(ctx contractapi.TransactionContextInterface, id string) (*Bidding_contractsign_BCC, error) {
	Json, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if Json == nil {
		return nil, fmt.Errorf("the app %s does not exist", id)
	}

	var bid_contra_bbc Bidding_contractsign_BCC
	err = json.Unmarshal(Json, &bid_contra_bbc)
	if err != nil {
		return nil, err
	}

	return &bid_contra_bbc, nil
}

func main() {
	tabakochaincode, err := contractapi.NewChaincode(&smartcontract{})
	if err != nil {
		log.Panicf("Error creating asset-transfer-basic chaincode: %v", err)
	}

	if err := tabakochaincode.Start(); err != nil {
		log.Panicf("Error starting asset-transfer-basic chaincode: %v", err)
	}
}
