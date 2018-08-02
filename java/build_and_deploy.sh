#!/bin/bash

#############
### BUILD ###
#############

build_and_tag_docker () {
    docker build -t ${ECR_NAME} .
    docker tag ${ECR_NAME}:latest ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/${ECR_NAME}:${IMAGE_VERSION}
}

compile_docker_image () {
    echo "Compiling the project to generate .jar"
    mvn clean install -DskipTests
    mvn clean package -DskipTests
    if [ $? -eq 0 ]; then
        echo "Compiled with Sucess, building the new docker image"
    else
        echo "Maven FAILED to compile, please check Jenkins errors"
        exit 1
    fi
}

build_docker_image () {
    build_and_tag_docker
    if [ $? -eq 0 ]; then
        echo "Build executed, pushing the image to Amazon Repository"
    else
        echo "Maven FAILED to compile, please check Jenkins errors"
        exit 1
    fi
}

push_docker_image () {
    docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/${ECR_NAME}:${IMAGE_VERSION}
    if [ $? -eq 0 ]; then
        echo "Image pushed to Amazon Repository"
    else
        echo "push FAILED, please check Jenkins errors"
        exit 1
    fi
}

#############
### DEPLOY ##
#############

get_running_tasks () {
    DOCKER_STATUS=`aws ecs describe-services --cluster ${ECS_CLUSTER} --services ${ECS_SERVICE} --profile ${AWS_PROFILE} | jq '.services[] | .deployments[] | .runningCount' | sed 's/"//g'`
}

check_docker_status () {
    get_running_tasks
    while [ "${DOCKER_STATUS}" != "0" ]; do
        echo "############################################"
        echo "Current docker still running, waiting 5 seconds to start the new one"
        echo "############################################"
        sleep 5
        get_running_tasks
    done
    echo "############################################"
    echo "Current docker stopped, deploying the new version"
    echo "############################################"
}

deploy_status () {
    get_running_tasks
    while [ "${DOCKER_STATUS}" != "${ECS_TASK_NUMBER}" ]; do
        echo "############################################"
        echo "Docker is starting, waiting 10 seconds"
        echo "############################################"
        sleep 10
        get_running_tasks
    done
    echo "############################################"
    echo "All ${ECS_TASK_NUMBER} docker started"
    echo "############################################"
}

deploy_docker_image () {
    echo "####################################################"
    echo "## Deploy started on cluster ${ECS_CLUSTER} ##"
    echo "####################################################"
    echo "## Updating ${ECS_SERVICE} ##"
    echo "############################################"
    aws ecs update-service --cluster ${ECS_CLUSTER} --service ${ECS_SERVICE} --desired-count 0 --profile ${AWS_PROFILE}
    if [ $? -eq 0 ]; then
        check_docker_status
        aws ecs update-service --cluster ${ECS_CLUSTER} --service ${ECS_SERVICE} --desired-count ${ECS_TASK_NUMBER} --profile ${AWS_PROFILE}
        #deploy_status
        echo "##########################################"
        echo "## New docker is launching on instances ##"
        echo "##########################################"
    else
        echo "####################################################"
        echo "####################################################"
        echo "Please check if service ${ECS_SERVICE} exist"
        echo "####################################################"
        echo "####################################################"
        exit 0
    fi
}

deploy_prod_docker_image () {
    sed -i "s/IMAGE_VERSION/${IMAGE_VERSION}/g" ./deploy/app.json

    TASK_DEFINITION=`aws ecs register-task-definition \
    --cli-input-json file://./deploy/app.json \
    --network-mode bidge \
    --profile "${AWS_PROFILE}" \
    | jq '.taskDefinition | .revision'`

    aws ecs update-service \
    --cluster "${ECS_CLUSTER}" \
    --service "${ECS_SERVICE}" \
    --desired-count "${ECS_TASK_NUMBER}" \
    --task-definition prd-plataforma-de-negocio:"${TASK_DEFINITION}" \
    --deployment-configuration maximumPercent="${MAXIMUM_HEALTH}",minimumHealthyPercent="${MINIMUM_HEALTH}" \
    --profile "${AWS_PROFILE}"
}

#################
### EXECUTION ###
#################

PIPELINE_STATUS=$1

case ${PIPELINE_STATUS} in
    build)
        compile_docker_image
        build_docker_image
        push_docker_image
        ;;
    deploy)
        deploy_docker_image
        ;;
    production-deploy)
        compile_docker_image
        build_docker_image
        push_docker_image
        deploy_prod_docker_image
        ;;
    *)
        echo "############################################"
        echo "Select between build, or deploy"
        echo "############################################"
        ;;
esac
