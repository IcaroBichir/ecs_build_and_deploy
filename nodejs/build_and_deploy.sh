#!/bin/bash
AWS_ACCOUNT_ID=
AWS_REGION=

#############
### TEST ####
#############

run_tests () {
    npm install --progress=false
    if [ $? -eq 0 ]; then
    npm run test:ci
    else
        echo "npm FAILED to install, please check Jenkins errors"
        exit 1
    fi
}

#############
### BUILD ###
#############

build_and_push_docker_image () {
    docker build -t "${AWS_ECR_NAME}" .
    if [ $? -eq 0 ]; then
        docker tag "${AWS_ECR_NAME}":latest "${AWS_ACCOUNT_ID}".dkr.ecr.sa-east-1.amazonaws.com/"${AWS_ECR_NAME}":"${AWS_IMAGE_VERSION}"
        if [ $? -eq 0 ]; then
            docker push "${AWS_ACCOUNT_ID}".dkr.ecr."${AWS_REGION}".amazonaws.com/"${AWS_ECR_NAME}":"${AWS_IMAGE_VERSION}"
            if [ $? -eq 0 ]; then
                echo "Image builded, tagged and pushed to Amazon Repository"
            else
                exit 1
            fi
        else
            exit 1
        fi
    else
        exit 1
    fi
}

#############
### DEPLOY ##
#############

deploy_docker_image () {
    sed -i "s/AWS_IMAGE_VERSION/${AWS_IMAGE_VERSION}/g" ./deploy/"${BRANCH_NAME}".json

    build_and_push_docker_image
    TASK_DEFINITION=`aws ecs register-task-definition \
    --cli-input-json file://./deploy/"${BRANCH_NAME}".json \
    --network-mode bridge \
    --requires-compatibilities EC2 \
    | jq '.taskDefinition | .revision'`

    aws ecs update-service \
    --cluster "${AWS_ECS_CLUSTER}" \
    --service "${BRANCH_NAME}"-"${AWS_ECR_NAME}" \
    --desired-count "${AWS_ECS_TASK_NUMBER}" \
    --task-definition "${BRANCH_NAME}"-"${AWS_ECR_NAME}":"${TASK_DEFINITION}"
}

#################
### EXECUTION ###
#################

PIPELINE_STEP=$1

case ${PIPELINE_STEP} in
    test)
        run_tests
        ;;
    deploy)
        deploy_docker_image
        ;;
    *)
        echo "############################################"
        echo "Select between test and deploy"
        echo "############################################"
        exit 1
        ;;
esac
