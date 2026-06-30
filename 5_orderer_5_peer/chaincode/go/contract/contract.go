package main

import (
	"encoding/json"
	"fmt"
	"log"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
	//"github.com/hyperledger/fabric-chaincode-go/shim"
	//"math/rand"
)

type smartcontract struct {
	contractapi.Contract
}

type Job_application struct {
	IDCV         string `json:"idcv"`
	Student_sign string `json:"student_sign"`
	IPFS_address string `json:"ipfs_address"`
}

type POA struct {
	Student_id   string `json:"student_id"`
	Student_sign string `json:"student_sign"`
	IDCV         string `json:"idcv"`
	Company_sign string `json:"company_sign"`
}

type Job_opening struct {
	Company_id   string `json:"company_id"`
	IPFS_address string `json:"ipfs_address"`
	Company_sign string `json:"company_sign"`
	Deadline     string `json:"deadline"`
}

func (s *smartcontract) InitLedger(ctx contractapi.TransactionContextInterface) error {

	job_app := Job_application{IDCV: "00", Student_sign: " ", IPFS_address: " "}
	Json, err := json.Marshal(job_app)
	err = ctx.GetStub().PutState(job_app.IDCV, Json)
	if err != nil {
		return fmt.Errorf("failed to put  state, %v", err)
	}

	job_open := Job_opening{Company_id: "01", IPFS_address: "", Company_sign: " ", Deadline: " "}
	Json, err = json.Marshal(job_open)
	err = ctx.GetStub().PutState(job_open.Company_id, Json)
	if err != nil {
		return fmt.Errorf("failed to put  state, %v", err)
	}
	poa := POA{Student_id: "02", Student_sign: " ", IDCV: " ", Company_sign: " "}
	Json, err = json.Marshal(poa)
	err = ctx.GetStub().PutState(poa.Student_id, Json)
	if err != nil {
		return fmt.Errorf("failed to put  state, %v", err)
	}
	return nil
}
func (s *smartcontract) Delete(ctx contractapi.TransactionContextInterface, id string) error {
        return ctx.GetStub().DelState(id)
}
//#Job_application-------------------------------------
func (s *smartcontract) GetAllJobApp(ctx contractapi.TransactionContextInterface) ([]*Job_application, error) {
	results, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, err
	}
	defer results.Close()

	var job_apps []*Job_application
	for results.HasNext() {
		queryresponse, err := results.Next()
		if err != nil {

		}

		var job_app Job_application
		err = json.Unmarshal(queryresponse.Value, &job_app)
		if err != nil {
			return nil, err
		}
		job_apps = append(job_apps, &job_app)
	}

	return job_apps, nil
}

func (s *smartcontract) CreateJobApp(ctx contractapi.TransactionContextInterface, idcv string, sign, ipfs_address string) error {

	Json, err := json.Marshal(Job_application{IDCV: idcv, Student_sign: sign, IPFS_address: ipfs_address})
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(idcv, Json)
}

func (s *smartcontract) ReadJobApp(ctx contractapi.TransactionContextInterface, id string) (*Job_application, error) {
	Json, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if Json == nil {
		return nil, fmt.Errorf("the app %s does not exist", id)
	}

	var job_app Job_application
	err = json.Unmarshal(Json, &job_app)
	if err != nil {
		return nil, err
	}
	if job_app.Student_sign == ""{
		return nil,fmt.Errorf("studend not signed")
	}
	if job_app.IPFS_address == ""{
		return nil ,fmt.Errorf(" No IPFS Address uploaded")
	}

	return &job_app, nil
}

//#POA-------------------------------------------------

func GetAllPOA(ctx contractapi.TransactionContextInterface) ([]*POA, error) {
	results, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, err
	}
	defer results.Close()

	var poas []*POA
	for results.HasNext() {
		queryresponse, err := results.Next()
		if err != nil {
			return nil, err
		}

		var poa POA
		err = json.Unmarshal(queryresponse.Value, &poa)
		if err != nil {
			return nil, err
		}
		poas = append(poas, &poa)
	}

	return poas, nil
}

func (s *smartcontract) ReadPOA(ctx contractapi.TransactionContextInterface, id string) (*POA, error) {
	batjson, err := ctx.GetStub().GetState(id)

	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if batjson == nil {
		return nil, fmt.Errorf("the batch %s does not exist", id)
	}

	var poa POA
	err = json.Unmarshal(batjson, &poa)
	if err != nil {
		return nil, err
	}
	if poa.Company_sign != "" {
		//return nil, fmt.Errorf("failed:  not Read again ")
	}
	return &poa, nil
}

func (s *smartcontract) CreatePOA(ctx contractapi.TransactionContextInterface, id string, sign string, idcv string) error {
	batch := POA{Student_id: id, Student_sign: sign, IDCV: idcv, Company_sign: ""}
	batchJSON, err := json.Marshal(batch)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(id, batchJSON)
}

func (s *smartcontract) UpdatePOASign(ctx contractapi.TransactionContextInterface, id string, sign string) error {
        batjson, err := ctx.GetStub().GetState(id)
        if err != nil {
                return fmt.Errorf("failed to read from world state: %v", err)
        }
        if batjson == nil {
                return  fmt.Errorf("the batch %s does not exist", id)
        }

        var poa POA
        err = json.Unmarshal(batjson, &poa)
        if err != nil {
                return  err
        }

	poa.Company_sign = sign
	batchjson, err := json.Marshal(poa)
	if err != nil {
		return fmt.Errorf("failed to marshal batch: %v", err)
	}
	return ctx.GetStub().PutState(id, batchjson)
}

//#Job_opening-----------------------------------------

func (s *smartcontract) GetAllJob_open(ctx contractapi.TransactionContextInterface) ([]*Job_opening, error) {
	results, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, err
	}
	defer results.Close()

	var job_opens []*Job_opening
	for results.HasNext() {
		queryresponse, err := results.Next()
		if err != nil {
			return nil, err
		}

		var job_open Job_opening
		err = json.Unmarshal(queryresponse.Value, &job_open)
		if err != nil {
			return nil, err
		}
		job_opens = append(job_opens, &job_open)
	}
	return job_opens, nil
	/*
		sol := &solution{}
		sol.result = aps
		return sol, nil
	*/
}

func (s *smartcontract) ReadJobOpen(ctx contractapi.TransactionContextInterface, id string) (*Job_opening, error) {
	Json, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if Json == nil {
		return nil, fmt.Errorf("the ap %s does not exist", id)
	}

	var job_open Job_opening
	err = json.Unmarshal(Json, &job_open)
	if err != nil {
		return nil, err
	}

	return &job_open, nil
}

func (s *smartcontract) CreateJobOpen(ctx contractapi.TransactionContextInterface, company_id string, ipfs_address string, sign string, deadline string) error {
	Json, err := json.Marshal(Job_opening{Company_id: company_id, IPFS_address: ipfs_address, Company_sign: sign, Deadline: deadline})
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(company_id, Json)
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
